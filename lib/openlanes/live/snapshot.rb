# frozen_string_literal: true

module OpenLanes
  module Live
    # Everything the page shows about this node, as one hash in exactly the
    # shape of `Snapshot` in `web/src/api/types.ts`.
    #
    # Built from what already says it: the dispatcher's {Engine::Board} for
    # who is running and what they spent, the `.plans` tree for each plan's
    # state, questions and pull requests, the registry for the stations, the
    # adapter for the models and their prices. Nothing here is a second copy
    # of any of them. `spec/openlanes/live/snapshot_spec.rb` holds the keys
    # to the page's fixture, level by level, so a field renamed on one side
    # fails the other's suite.
    class Snapshot
      # Plan states finished with, kept off "Choose an existing plan".
      FINISHED = %i[approved deployed discarded].freeze

      # @param board [OpenLanes::Engine::Board]
      # @param tree [OpenLanes::Plans::Tree]
      # @param agents [OpenLanes::Agents::Registry]
      # @param node [OpenLanes::Live::Node]
      # @param repo [String]
      # @param project [String]
      # @param description [String, nil]
      # @param seq [Integer]
      # @param at [Time]
      # @param started_at [Time, nil] the run's start, wall clock
      # @param claims [OpenLanes::Live::Claims, nil]
      # @param run_state [OpenLanes::Live::RunState]
      # @param meter [OpenLanes::Live::Meter]
      # @param log [Array<Hash>] `LogLine`s, newest last
      # @param adapter [OpenLanes::Adapters::Base] whose models the page offers
      # @param judge [#call, nil] a second opinion on whether a question asks
      #   to choose ({ChoiceJudge}); nil leaves the parser's verdict alone
      def initialize(board:, tree:, agents:, node:, repo:, project:, seq:, description: nil, at: Time.now,
        started_at: nil, claims: nil, run_state: RunState.new, meter: Meter.new, log: [],
        adapter: Adapters.for(Adapters::DEFAULT), judge: Live.choice_judge)
        @board = board
        @tree = tree
        @agents = agents
        @node = node
        @repo = repo
        @project = project
        @description = description
        @seq = seq
        @at = at
        @started_at = started_at
        @claims = claims
        @run_state = run_state
        @meter = meter
        @log = log
        @adapter = adapter
        @judge = judge
      end

      # @return [Hash]
      def to_h
        subjects = @tree.reload.subjects
        mine = ours(subjects)
        { seq:         @seq,
          at:          iso(@at),
          node:        @node.wire(heartbeat_at: @at, me: true),
          repo:        @repo,
          project:     @project,
          description: @description,
          run:         run(mine),
          stations:    Stations.all(@agents).map(&:wire),
          plans:       mine,
          backlog:     backlog(subjects, mine.map { it[:ordinal] }),
          bombs:       bombs(subjects),
          models:      @adapter.models.map(&:wire),
          autocompact: Adapters::AUTOCOMPACT / 100.0,
          log:         @log }
      end

      private

      # ---- run --------------------------------------------------------------

      # @param plans [Array<Hash>]
      # @return [Hash]
      def run(plans)
        { status:         run_status,
          started_at:     @started_at && iso(@started_at),
          up:             @board.up.to_i,
          down:           @board.down.to_i,
          cost:           plans.sum { it[:cost] }.round(4),
          agents_working: @board.running.to_i }
      end

      # @return [String]
      def run_status
        return "idle" if @board.running.to_i.zero? && @board.rows.empty? && @board.status == :running

        @board.status.to_s
      end

      # ---- plans ------------------------------------------------------------

      # The plans this node is working on: the board's, and any it has
      # claimed but not yet started.
      #
      # @param subjects [Array<OpenLanes::Plans::Subject>]
      # @return [Array<Hash>]
      def ours(subjects)
        ordinals = (@board.plans + Array(@claims&.held)).uniq
        subjects.select { |s| ordinals.include?(s.feature.ordinal.to_s) }.map { |s| plan(s) }
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Hash] `Plan`
      def plan(subject)
        ordinal = subject.feature.ordinal.to_s
        state = Plans::PlanState.for(subject.feature.path)
        stages = state.stages
        rows = @board.rows.select { it.ordinal == ordinal }
        spent = @meter.for(ordinal, method(:price))
        started = @meter.started_at(ordinal)
        { ordinal:,
          title:       subject.feature.title,
          slug:        subject.feature.slug,
          status:      status(subject.status),
          lane:        Plans::Spec.for(subject).lane.to_s,
          station:     Stations.key_for(subject.status.key, before: stages.last&.fetch("from", nil)&.to_sym).to_s,
          up:          spent[:up],
          down:        spent[:down],
          cost:        spent[:cost],
          started_at:  started && iso(started),
          elapsed:     started ? (@at - started).round : 0,
          cars:        rows.map { car(it, subject, stages) },
          pr:          pull_request(subject),
          questions:   questions(subject, state),
          interrupted: interrupted(stages, rows),
          claimed_by:  claimed_by(ordinal),
          unacked:     Plans.mailbox(subject.feature.path).unacked,
          last_known:  last_known(state),
          locked:      Plans::Lock.read(subject.feature.path)&.to_json_hash }
      end

      # @param status [OpenLanes::Plans::Status]
      # @return [Hash] `Status`
      def status(status) = { key: status.key.to_s, emoji: status.emoji, label: status.label }

      # @param subjects [Array<OpenLanes::Plans::Subject>]
      # @param taken [Array<String>] ordinals already on the board
      # @return [Array<Hash>] plans a person could add to this run
      def backlog(subjects, taken)
        subjects.reject { |s| taken.include?(s.feature.ordinal.to_s) || FINISHED.include?(s.status.key) }
                .reject { |s| foreign?(s.feature.ordinal.to_s) }
                .map do |s|
          { ordinal: s.feature.ordinal.to_s, title: s.feature.title, status: status(s.status),
            lane: Plans::Spec.for(s).lane.to_s }
        end
      end

      # Every 💣 in the tree that is not another machine's, on the board or
      # not: a bomb halts the whole run, so the page shows it whatever this
      # node is working on (plan 009).
      #
      # @param subjects [Array<OpenLanes::Plans::Subject>]
      # @return [Array<Hash>] `Bomb`
      def bombs(subjects)
        aging = Lifecycle::Aging.new(tree: @tree, now: @at)
        subjects.select { it.status.key == :bomb && !foreign?(it.feature.ordinal.to_s) }.map do |s|
          resume = Plans::PlanState.for(s.feature.path).resume_until
          { plan:          s.feature.ordinal.to_s,
            slug:          s.feature.slug,
            blocked_md:    s.read("blocked.md").to_s,
            blocked_since: iso(aging.started_at(s)),
            resume_until:  resume && iso(resume) }
        end
      end

      # ---- cars -------------------------------------------------------------

      # @param row [OpenLanes::Engine::Board::Row]
      # @param subject [OpenLanes::Plans::Subject]
      # @param stages [Array<Hash>]
      # @return [Hash] `Car`
      def car(row, subject, stages)
        { key:           row.key,
          agent:         row.agent,
          role:          row.role.to_s,
          round:         row.round,
          rounds:        row.rounds,
          model:         model_id(row.model),
          effort:        stages.rfind { it["agent"] == row.agent }&.fetch("effort", nil),
          state:         car_state(row, subject),
          phase:         row.phase&.to_s,
          message:       row.message.to_s,
          history:       Array(row.history).first(Engine::Board::Row::HISTORY),
          up:            row.up.to_i,
          down:          row.down.to_i,
          context:       row.context,
          context_limit: price(row.model)&.context,
          elapsed:       row.elapsed.to_i,
          remaining:     row.remaining,
          held:          @run_state.car_held?(row.key),
          next_model:    next_model(row) }
      end

      # The model a person queued for the agent's next round, until a round
      # runs on it: from then on it is the model, not the next one.
      #
      # @param row [OpenLanes::Engine::Board::Row]
      # @return [String, nil]
      def next_model(row)
        queued = @run_state.model_for(row.key)
        queued unless queued == model_id(row.model)
      end

      # A running agent on a plan that has stopped for a question is stuck,
      # not working: the page says so rather than spinning.
      #
      # @return [String]
      def car_state(row, subject)
        return "stuck" if row.running? && %i[blocked product_blocked].include?(subject.status.key)

        row.state.to_s
      end

      # @param label [String, nil] a {Agents::Profile#label}: `opus`, or `codex:gpt-5`
      # @return [String] the full model id when the adapter knows it
      def model_id(label)
        name = label.to_s.split(":", 2).last
        adapter_for(label)&.model_entry(name)&.id || name
      end

      # The catalogue's entry for a model: its prices, and its context window.
      #
      # @param label [String, nil]
      # @return [OpenLanes::Adapters::Model, nil]
      def price(label) = adapter_for(label)&.model_entry(label.to_s.split(":", 2).last)

      # @param label [String, nil]
      # @return [OpenLanes::Adapters::Base, nil]
      def adapter_for(label)
        prefix = label.to_s.include?(":") ? label.to_s.split(":", 2).first : Adapters::DEFAULT
        Adapters.known?(prefix) ? Adapters.for(prefix) : nil
      end

      # ---- pull request, interruption, claim --------------------------------

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Hash, nil] `PullRequest`
      def pull_request(subject)
        pr = subject.pull_requests.find(&:open?) || subject.pull_requests.last or return nil
        { number: pr.number.to_s[/\d+/].to_i, url: pr.url, state: pr_state(pr, subject), ci: nil, merged_at: nil }
      end

      # @return [String]
      def pr_state(pr, subject)
        return "merged" if pr.merged?
        return "closed" unless pr.open?

        { rejected: "rejected", approved: "approved" }.fetch(subject.status.key, "open")
      end

      # The latest stage, when it is an interruption nobody has resumed.
      #
      # @param stages [Array<Hash>]
      # @param rows [Array<OpenLanes::Engine::Board::Row>]
      # @return [Hash, nil]
      def interrupted(stages, rows)
        last = stages.last
        return nil unless last && last["status"] == "Interrupted" && rows.none? { it.agent == last["agent"] && it.running? }

        { agent: last["agent"], at: last["finished_at"] || last["started_at"], note: last["note"].to_s }
      end

      # Where each interrupted agent stood, as the next round will read it.
      # Read-only: an unacked count or a resume record never changes a round.
      #
      # @param state [OpenLanes::Plans::PlanState]
      # @return [Array<Hash>] `LastKnown`, one per agent
      def last_known(state)
        state.last_known_states.map do |agent, entry|
          { agent:, source: entry.source, at: entry.at, round: entry.round, status: entry.status,
            next_step: entry.next_step, note: entry.note }
        end
      end

      # @param ordinal [String]
      # @return [String, nil] the node id, without its checkout
      def claimed_by(ordinal) = @claims&.held_by(ordinal)&.then { it.split(":").first }

      # @param ordinal [String]
      # @return [Boolean]
      def foreign?(ordinal) = !@claims.nil? && @claims.foreign?(ordinal)

      # ---- questions --------------------------------------------------------

      # The questions `blocked.md` still asks, each with its context, the
      # options it offers (D3), and who asked; then the harness's own
      # requests for more time or rounds (E1).
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param state [OpenLanes::Plans::PlanState]
      # @return [Array<Hash>] `Question`
      def questions(subject, state)
        blocked(subject, state) + Engine::Extensions.questions(subject, state)
      end

      # @return [Array<Hash>] `Question`, from `blocked.md`
      def blocked(subject, state)
        open = Lifecycle::Unblocker.questions(subject).reject(&:answered)
        return [] if open.empty?

        bodies = Plans::BlockedFile.bodies(subject.read("blocked.md").to_s)
        asker = state.signatures.rfind { it["status"] == "Blocked" }
        asked_at = asker&.fetch("at", nil) || iso(File.mtime(File.join(subject.feature.path, "blocked.md")))
        open.map { |q| question(subject, q, bodies.fetch(q.number, ""), asker, asked_at) }
      end

      # @return [Hash]
      def question(subject, open, body, asker, asked_at)
        id = "#{subject.feature.ordinal}/B#{open.number}"
        choices = choices(open.heading, body)
        { id:,
          number:   open.number,
          kind:     "block",
          heading:  open.heading.sub(Plans::Choices::YES_NO, "").strip,
          body:     choices ? choices.context : body.strip,
          agent:    asker&.fetch("agent", nil),
          owner:    subject.status.key == :product_blocked ? "product" : "technical",
          options:  choices&.to_a,
          held:     @run_state.question_held?(id),
          asked_at: }
      end

      # The options a question offers, or nil for one that wants words.
      #
      # A question its agent marked yes/no (W30) is taken at its word. Any
      # other the parser found options in goes past the judge, which may say
      # the list was not a choice after all; it is never asked about a
      # question the parser found nothing in, since there would be no buttons
      # to show.
      #
      # @param heading [String]
      # @param body [String]
      # @return [OpenLanes::Plans::Choices, nil]
      def choices(heading, body)
        return Plans::Choices.yes_no(body) if heading.match?(Plans::Choices::YES_NO)

        found = Plans::Choices.parse(body) or return nil
        return found if body.match?(Plans::Choices::YES_NO)

        @judge&.call(body) == false ? nil : found
      end

      # @param time [Time]
      # @return [String]
      def iso(time) = time.utc.iso8601
    end
  end
end
