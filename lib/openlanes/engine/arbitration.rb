# frozen_string_literal: true

module OpenLanes
  module Engine
    # The engine step that runs `arbitrator` (M7, M8, M9).
    # It is a side call, not a plan state: the agent is read-only, so the
    # registry never routes a state to it, and every ruling lands the plan
    # in a state that already exists.
    #
    # Once a tick, before agents are assigned, {#tick} asks each plan for a
    # trigger, in the spec's order. The agent runs off the loop's thread, as
    # a verification look does: an opus run of up to ten minutes inside the
    # tick froze reaping, kills, the board and dispatch for all of it. The
    # plans it is asked about are {#asking} until the answer is applied, on
    # the loop's thread, on the first tick after it came back. {#holds?}
    # keeps a capped plan from its builders.
    #
    # An answer that cannot be read rules nothing, so the trigger still
    # fires: it is asked again only after {BACKOFF} seconds, doubled each
    # time, and after {ATTEMPTS} the engine gives up on it for this run. A
    # capped plan given up on goes to ⭕️, since it is held from its builders
    # and would otherwise wait for a ruling that never comes.
    class Arbitration
      # Builders whose signatures may carry an appeal, and who may raise a dispute.
      BUILDERS = Agents::Names::BUILDERS.freeze

      # A dispute is mail to the arbitrator whose body opens with this word.
      DISPUTE = /\Adispute:/i

      # Unreadable answers one trigger gets before the engine stops asking.
      ATTEMPTS = 3

      # Seconds before an unreadable answer's trigger is asked again.
      BACKOFF = 60

      # What one arbitration came to.
      #
      # @!attribute [r] plan
      #   @return [String] the plan's ordinal
      # @!attribute [r] trigger
      #   @return [String]
      # @!attribute [r] effects
      #   @return [OpenLanes::Arbitration::Effects::Result, nil] nil when the answer could not be read
      # @!attribute [r] error
      #   @return [String, nil] why it could not
      Outcome = Data.define(:plan, :trigger, :effects, :error)

      # One question put to the agent off the loop's thread, and its answer.
      Asked = Data.define(:plan, :found, :round, :answer, :error)

      # @param tree_dir [String] the `.plans` directory
      # @param agents [OpenLanes::Agents::Registry]
      # @param github [OpenLanes::Vcs::GitHub]
      # @param ask [#call] given the agent, the plan and the trigger text,
      #   returns the agent's final answer; the default is an {Asker}
      # @param executor [#call] given the brief, builds the executor the
      #   default {Asker} runs; the run passes one carrying its own
      #   `--timeout`, `--model`, `--max-tokens` and `--user-config`
      # @param max_rejections [#call] `merge.max_rejections`
      # @param quality [#call] `desired_codebase_quality`; only `mvp` checks a
      #   `review-ok-not-perfect` verdict (M9: `medium` was dropped with R4)
      # @param effects [OpenLanes::Arbitration::Effects]
      # @param clock [#call] the time now, for {BACKOFF}
      def initialize(tree_dir:, agents:, github:, ask: nil, root: nil, executor: nil,
        max_rejections: -> { Config.current.max_rejections },
        quality: -> { Config.current.desired_codebase_quality },
        effects: OpenLanes::Arbitration::Effects.new(tree_dir:, github:), clock: -> { Time.now })
        @tree_dir = tree_dir
        @agents = agents
        @github = github
        root ||= File.dirname(tree_dir)
        @ask = ask || Asker.new(executor: executor || ->(brief) { Execution.executor(root:, instructions: brief) })
        @max = max_rejections
        @quality = quality
        @effects = effects
        @clock = clock
        @thread = nil
        @asking = []
        @failures = {}
        @labels = {}
      end

      # Called by {Verification::Outcome} as a rejection reaches the cap.
      # The ruling itself runs on the next tick, where every trigger is
      # asked in one place.
      #
      # @param plan [OpenLanes::Plans::Subject]
      # @param count [Integer]
      # @param max [Integer]
      # @return [void]
      def call(plan:, count:, max:) = self.class.call(plan:, count:, max:)

      # The same notice, for a {Verification::Outcome} built without a run
      # to arbitrate in.
      #
      # @param plan [OpenLanes::Plans::Subject]
      # @param count [Integer]
      # @param max [Integer]
      # @return [void]
      def self.call(plan:, count:, max:)
        UI.log("rejected #{count} of #{max}: at the cap, the arbitrator rules next", level: :warn, plan: plan.feature.ordinal.to_s)
      end

      # Applies the answers that came back since the last tick, or starts
      # asking about the plans that have a trigger. Never both in one tick,
      # and never waits for the agent.
      #
      # @param subjects [Array<OpenLanes::Plans::Subject>] plans no agent is
      #   running on, read fresh, the ones being asked about included
      # @return [Array<Outcome>] one per answer applied, often none
      def tick(subjects)
        if @thread && !@thread.alive?
          asked = @thread.value
          @thread = nil
          @asking = []
          return asked.map { settle(it) }
        end
        start(subjects) unless @thread
        []
      end

      # @return [Array<String>] ordinals being asked about: no agent may
      #   start on them and no rename may touch them until the answer is applied
      def asking = @asking.dup

      # @return [Boolean] whether an answer is awaited, or back and not yet
      #   applied: a run may not end before {#tick} has had it
      def busy? = !@thread.nil?

      # @return [void] waits for the agent under way
      def join = @thread&.join

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Hash, nil] `{ trigger:, key:, appellant:, message:, note: }`,
      #   the first that fires in the spec's order, nil when none does
      def triggered(subject)
        state = Plans::PlanState.for(subject.feature.path)
        appeal(state) || dispute(state) || cap(subject, state) || passed_check(subject, state)
      end

      # A plan at 🔴 whose rejections reached the cap belongs to the
      # arbitrator, not to backend-coder and frontend-coder.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean]
      def holds?(subject) = !cap(subject, Plans::PlanState.for(subject.feature.path)).nil?

      private

      # Opens a stage for every plan with a trigger not backing off, and
      # asks about them on one thread, one after another.
      #
      # @return [void]
      def start(subjects)
        agent = @agents.find(OpenLanes::Arbitration::AGENT)
        pending = subjects.filter_map do |subject|
          found = triggered(subject) or next
          next if backing_off?(subject, found)

          state = Plans::PlanState.for(subject.feature.path)
          round = state.rulings.size + 1
          # A stage per attempt, so each unreadable answer keeps its own record.
          state.stage!(agent: agent.name, round:, reset: true, status: "Started", started_at: @clock.call.iso8601)
          [subject, found, round, brief(subject, found)]
        end
        return if pending.empty?

        @asking = pending.map { it.first.feature.ordinal.to_s }
        @thread = Thread.new do
          Thread.current.report_on_exception = false
          pending.map { |subject, found, round, brief| ask(agent, subject, found, round, brief) }
        end
      end

      # On the agent's thread: everything is caught, so `#value` never
      # raises into the loop.
      #
      # @return [Asked]
      def ask(agent, subject, found, round, brief)
        Asked.new(plan: subject.feature.ordinal.to_s, found:, round:, answer: @ask.call(agent, subject, brief), error: nil)
      rescue StandardError => e
        Asked.new(plan: subject.feature.ordinal.to_s, found:, round:, answer: nil, error: e.message)
      end

      # On the loop's thread. The plan is read again, since the folder may
      # have moved while the agent ran, and its trigger asked again: one
      # that no longer fires (a person ruled, the appeal was answered) is
      # left alone rather than ruled on stale.
      #
      # @param asked [Asked]
      # @return [Outcome]
      def settle(asked)
        agent = @agents.find(OpenLanes::Arbitration::AGENT)
        found = asked.found
        subject = find(asked.plan)
        raise Error, asked.error if asked.error
        raise Error, "the plan is gone" unless subject
        raise Error, "the #{found[:trigger]} no longer stands" unless triggered(subject)&.fetch(:key) == found[:key]

        ruling = OpenLanes::Arbitration.ruling(asked.answer)
        result = @effects.apply(plan: subject, ruling:, trigger: found[:trigger], round: asked.round, appellant: found[:appellant])
        @failures.delete(key(asked.plan, found))
        close(asked, agent, "Completed", ruling.headline) do |state|
          state.ack!(found[:message], by: agent.name) if found[:message]
        end
        Outcome.new(plan: asked.plan, trigger: found[:trigger], effects: result, error: nil)
      # StandardError: an effect that fails after the folder moved raises
      # Errno, not an OpenLanes::Error, and the stage must still be closed.
      rescue StandardError => e
        failed(asked, agent, e.message)
      end

      # @return [Outcome]
      def failed(asked, agent, message)
        failure = @failures[key(asked.plan, asked.found)] = { count: (@failures.dig(key(asked.plan, asked.found), :count) || 0) + 1, at: @clock.call }
        note = "#{message} (attempt #{failure[:count]} of #{ATTEMPTS})"
        close(asked, agent, "Interrupted", note)
        UI.log("arbitration refused: #{note}", level: :warn, plan: asked.plan)
        give_up(asked) if failure[:count] >= ATTEMPTS
        Outcome.new(plan: asked.plan, trigger: asked.found[:trigger], effects: nil, error: message)
      end

      # @return [void]
      def give_up(asked)
        blocked = asked.found[:trigger] == "cap" && (subject = find(asked.plan)) &&
                  OpenLanes::Arbitration.block(subject, <<~MD)
                    # Blocked

                    ## B1 The arbitrator could not rule at the rejection cap

                    Its answer could not be read #{ATTEMPTS} times running; `openlanes state show --plan #{asked.plan}` has each attempt under `stages`.

                    a) Send it back to the builders for one more round. (Recommended)
                    b) Close the pull request and replan.
                  MD
        UI.log("arbitrator given up on after #{ATTEMPTS} unreadable answers#{"; plan blocked" if blocked}",
          level: :error,
          plan:  asked.plan)
      end

      # Closes the round's stage wherever the folder is now, whatever went
      # wrong: a stage left Started shows ⚖️ on the board for good.
      #
      # @yieldparam state [OpenLanes::Plans::PlanState]
      # @return [void]
      def close(asked, agent, status, note)
        subject = find(asked.plan) or return
        state = Plans::PlanState.for(subject.feature.path)
        yield state if block_given?
      ensure
        state&.stage!(agent: agent.name, round: asked.round, status:, note:, finished_at: @clock.call.iso8601)
      end

      # @return [Boolean]
      def backing_off?(subject, found)
        failure = @failures[key(subject.feature.ordinal.to_s, found)] or return false
        return true if failure[:count] >= ATTEMPTS

        @clock.call - failure[:at] < BACKOFF * (2**(failure[:count] - 1))
      end

      # @return [Array]
      def key(ordinal, found) = [ordinal, found[:key]]

      # @return [OpenLanes::Plans::Subject, nil] the plan as it stands now
      def find(ordinal) = Plans::Tree.new(dir: @tree_dir).find(ordinal)

      # @return [Hash, nil] the latest builder appeal no appeal ruling followed
      def appeal(state)
        last = state.rulings.select { it["kind"] == "appeal" }.map { Time.iso8601(it["at"]) }.max
        signature = state.signatures.rfind do |s|
          BUILDERS.include?(s["agent"]) && OpenLanes::Arbitration::Appeal.parse(s["note"]) && (last.nil? || Time.iso8601(s["at"]) > last)
        end
        signature && { trigger: "appeal", key: ["appeal", signature["at"]], appellant: signature["agent"], note: signature["note"] }
      end

      # @return [Hash, nil] the oldest unread dispute mailed to the arbitrator
      def dispute(state)
        message = state.messages.find do |m|
          m["to"] == OpenLanes::Arbitration::AGENT && m["read"] != "yes" && m["body"].to_s.strip.match?(DISPUTE)
        end
        message && { trigger: "dispute", key: ["dispute", message["number"]], message: message["number"], note: message["body"],
                     appellant: message["from"] }
      end

      # Keyed by the last cap ruling, since a count reset by one is a new cap.
      #
      # @return [Hash, nil]
      def cap(subject, state)
        return nil unless subject.status.key == :rejected

        count = OpenLanes::Arbitration.counter(agents: @agents).call(subject)
        max = @max.call
        return nil if count < max

        { trigger: "cap", key: ["cap", state.rulings.select { it["kind"] == "cap" }.last&.fetch("at", nil)], note: "rejected #{count} of #{max}" }
      end

      # At `mvp` only: a `review-ok-not-perfect` pull request at 👀 with no
      # `passed_check` ruling since staff-reviewer's latest signature. Keyed by that
      # signature, so a re-poll never re-runs it and a new review, after a
      # new push, does. 👀 only: a `too_lenient` ruling sends the plan to 🔴,
      # and the machine has that edge from 👀 alone.
      #
      # @return [Hash, nil]
      def passed_check(subject, state)
        return nil unless @quality.call == :mvp && subject.status.key == :in_review

        pull = subject.pull_requests.last or return nil
        reviewed = state.signatures.select { it["agent"] == Agents::Names::STAFF_REVIEWER && it["status"] == "Completed" }.map { Time.iso8601(it["at"]) }.max
        return nil unless reviewed
        return nil if state.rulings.any? { it["kind"] == "passed_check" && Time.iso8601(it["at"]) > reviewed }

        return nil unless labelled_ok_not_perfect?(pull, reviewed)

        { trigger: "passed_check", key: ["passed_check", reviewed.iso8601], note: "review-ok-not-perfect at mvp" }
      end

      # Asked of GitHub once per review rather than once per tick: staff-reviewer
      # sets its label before it signs (agents/staff-reviewer.md), so the
      # label a signature went with does not change under it.
      #
      # @return [Boolean]
      def labelled_ok_not_perfect?(pull, reviewed)
        @labels.fetch([pull.url || pull.number, reviewed]) do |cache_key|
          labels = @github.labels(number: Vcs::GitHub.number_of(pull.url || pull.number), repo: Vcs::GitHub.repo_of(pull.url))
          @labels[cache_key] = labels.include?(Plans::ReviewLabel::OK_NOT_PERFECT.name)
        end
      rescue Error
        false
      end

      # What the arbitrator is told on top of its definition.
      #
      # @return [String]
      def brief(subject, found)
        pull = subject.pull_requests.last
        ["Trigger: #{found[:trigger]}", ("Pull request: #{pull.url || pull.number}" if pull),
         ("Raised by: #{found[:appellant]}" if found[:appellant]), ("Says: #{found[:note]}" if found[:note]),
         "Plan folder: #{subject.feature.path}"].compact.join("\n")
      end

      # Runs the arbitrator through an executor in the main checkout (it
      # writes nothing, so it needs no worktree of its own), then reads its
      # final answer from the trace that very run wrote, named on its handle.
      class Asker
        # @param executor [#call] given the brief, returns the executor to run
        def initialize(executor:)
          @executor = executor
        end

        # @return [String] the agent's final answer, empty when none was read
        # @raise [OpenLanes::Error] when the run itself failed: an empty
        #   answer would read as "no ```ruling block" and hide why
        def call(agent, subject, brief)
          handle = Execution::Executor::Handle.new
          result = @executor.call(brief).call(agent, subject, handle:)
          raise Error, "the arbitrator's run failed: #{result.note}" unless result.ok

          trace = handle.trace
          return "" unless trace && File.exist?(trace)

          File.foreach(trace).filter_map { JSON.parse(it)["result"] if it.include?("\"result\"") }.last.to_s
        rescue JSON::ParserError
          ""
        end
      end
    end
  end
end
