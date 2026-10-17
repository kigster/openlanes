# frozen_string_literal: true

require "socket"

module OpenLanes
  module Engine
    # The loop. One tick a second: reap what finished and settle it against
    # the ledger, poll what is running for its latest line, start what is
    # dispatchable, heartbeat the state file, hand the screen a board.
    #
    # Nothing here guesses. An agent that finished says so in its document;
    # the state machine says whether the folder may move; the state file says
    # what an earlier run left behind. When the three disagree the row goes
    # red with the reason, and nobody is re-run to paper over it.
    class Dispatcher
      # One running invocation. `from` is the state the plan showed when the
      # agent was picked; `state` is the one it ran under, after any
      # `starts_as` rename. History is keyed by `state`: luke picked at ⭐
      # works at 🟡, and keying by ⭐ would offer him 🟡 afterwards as though
      # he had never been there (the 020.00 regression, run twice over).
      Job = Struct.new(:key,
        :task,
        :thread,
        :handle,
        :started_at,
        :file,
        :status,
        :message,
        :up,
        :down,
        :subagents,
        :result,
        :from,
        :state,
        :frame,
        :history,
        :context,
        :running,
        :rebase) do
        # @return [Boolean]
        def finished? = !thread.alive?
      end

      # A plan a person is throwing back (W9): its agents stopping, then its
      # worktree reset and its folder moved back one state. {Live::Commands}
      # holds on to it and replies once {#finished?}.
      #
      # @!attribute [r] ordinal
      #   @return [String]
      # @!attribute [r] status
      #   @return [String, nil] "done" or "refused", once it is over
      # @!attribute [r] reason
      #   @return [String, nil]
      Discard = Struct.new(:ordinal, :status, :reason) do
        # @return [Boolean]
        def finished? = !status.nil?
      end

      # What publishing did for one Completed build: the attempt with the
      # pull request noted, the plan read again so the row the publisher
      # recorded is in it, and whether the publisher refused.
      #
      # @!attribute [r] attempt
      #   @return [OpenLanes::Engine::Runner::Attempt]
      # @!attribute [r] subject
      #   @return [OpenLanes::Plans::Subject]
      # @!attribute [r] refused
      #   @return [Boolean]
      Published = Data.define(:attempt, :subject, :refused)

      # A blocked plan whose every question has an answer, being drained by
      # the agent that handles its state, on a thread of its own.
      Unblock = Struct.new(:ordinal, :thread, :outcome)

      # States a plan waits in for a person's answer. An answered 💣 is
      # drained like an answered ⭕.
      BLOCKED = %i[blocked product_blocked bomb].freeze

      # How long a settled row stays on the screen.
      LINGER = 10

      # Seconds a kill waits between STOP and SIGKILL.
      KILL_GRACE = 15

      # Seconds between rescans of the tree while a staying run has nothing
      # to do. A command from the page rescans at once; this interval is for
      # what arrives by other means: a folder edited by hand, `openlanes create`
      # typed in another terminal, a `blocked.md` answered in an editor.
      RESCAN = 5

      # Plans with nothing left to do, which an idle staying run reports
      # reaching rather than ending on. Not `Status#terminal?`:
      # only ❌ has no way out, while ✅ and 😎 can still roll back, and a
      # project whose plans all merged is finished in every sense a person
      # means. The page's backlog draws the same line.
      FINISHED = Live::Snapshot::FINISHED

      # The phase whose Completed notes are verdicts (approved, rejected,
      # slop). Anyone else's note is only a note.
      REVIEW_PHASE = "review"

      # @param runner [OpenLanes::Engine::Runner]
      # @param state [OpenLanes::Engine::StateFile, nil] nil under a dry run
      # @param rounds [Integer, nil] `--rounds`, a cap that only tightens
      # @param sleeper [Proc] how a tick waits; the suite passes a no-op
      # @param on_board [Proc, nil] receives a {Board} each tick
      # @param stay [Boolean] keep running past every fixed point, idle, until
      #   a person stops the run
      # @param rescan [Integer] idle ticks, about a second each, between
      #   rescans of the tree while staying
      # @param watch [OpenLanes::Engine::PrWatch, nil] the human-mode watch
      #   over open pull requests (M4); nil when nobody merges by hand or the
      #   run does not stay
      # @param converter [#call, nil] rewrites prose questions into choices
      #   (D9); nil, as without OPENROUTER_API_KEY, leaves them as written
      def initialize(runner:, state: nil, rounds: nil, sleeper: ->(seconds) { sleep(seconds) }, on_board: nil,
        stay: false, rescan: RESCAN, watch: nil, converter: Live.choice_converter)
        @runner = runner
        @watch = watch
        @watching = nil
        @waiting_on = {}
        @stay = stay
        @rescan = rescan
        @idle = false
        @idle_ticks = 0
        @wake = false
        @said = nil
        @state = state
        @rounds_cap = rounds
        @sleeper = sleeper
        @on_board = on_board
        @running = []
        @recent = []
        @attempts = []
        @history = Hash.new { |h, k| h[k] = [] }
        @finished_plans = []
        @preferred = {}
        @started_at = UI.monotonic
        @mutex = Mutex.new
        @before_tick = []
        @requeued = []
        @discarding = {}
        @fenced = []
        @unblocking = []
        @unblock_tried = {}
        @conversions = Conversions.new(converter:, runner:, find: method(:fresh_by))
        @locks = PlanLocks.new
      end

      # @return [Array<OpenLanes::Engine::Dispatcher::Job>]
      attr_reader :running

      # Mail over Redis, drained once a tick into the plans' `state.json`.
      # {Live::Session#attach} sets it; a run without Redis has none, and
      # loses nothing, because `mail send` wrote the file already.
      #
      # @return [OpenLanes::Live::Mail, nil]
      attr_accessor :mail

      # @return [OpenLanes::Engine::Runner]
      attr_reader :runner

      # Stopped rebases and how often each plan's has failed; see {Rebase}.
      #
      # @return [OpenLanes::Engine::Rebase]
      def rebases = @rebases ||= Rebase.new(agents: @runner.agents, executor: @runner.executor)

      # @return [OpenLanes::Engine::StateFile, nil] nil under a dry run
      def state_file = @state

      # @return [Array<OpenLanes::Engine::Runner::Attempt>]
      attr_reader :attempts

      # @return [Array<OpenLanes::Engine::Runner::Attempt>]
      def run
        resume_stranded
        loop do
          tick
          break if done?

          @sleeper.call(1)
        end
        @attempts
      end

      # One cycle. Public so the suite can drive it by hand.
      #
      # @return [void]
      def tick
        @before_tick.each { |hook| hook.call(self) }
        reap
        finish_discards
        unblock_answered
        convert_questions
        poll
        drain_mail
        watch_pull_requests
        # On threads: a kill waits out TERM before KILL, and the board must not.
        @running.each { |job| Thread.new { job.handle.kill!(grace: 0, reason: :quit) } } if Execution::Control.overdue?
        dispatch unless Execution::Control.quit? || resting?
        persist
        @on_board&.call(board)
      end

      # A run ends at a fixed point: nothing running and nothing left to
      # start. A staying run (the engine with its control room) never ends on
      # its own, not even once every plan is {FINISHED}: the page can create
      # the next plan at any moment, and a run that had quit would leave it
      # nowhere to go. Only a quit ends it (Stop All Local, Ctrl-C, SIGTERM),
      # once the agents have gone.
      #
      # @return [Boolean]
      def done?
        return false unless quiet?
        return true if Execution::Control.quit?
        return false if @stay

        next_dispatchable.nil?
      end

      # @return [Boolean] whether this run idles past its fixed points
      def stay? = @stay

      # Rescan on the next tick rather than at the end of the interval: a
      # command was applied, and what it changed should be acted on now.
      #
      # @return [void]
      def wake! = @wake = true

      # Kill from a view: STOP, {KILL_GRACE} seconds, SIGKILL, on a thread
      # so the tick is not held for fifteen seconds.
      #
      # @param key [String] a row's key
      # @return [void]
      def kill(key)
        job = @running.find { |j| j.key == key } or return
        Thread.new { job.handle.kill!(grace: KILL_GRACE) }
      end

      # More time, from a view.
      #
      # @param key [String]
      # @param seconds [Integer]
      # @return [void]
      def extend(key, seconds)
        @running.find { |j| j.key == key }&.handle&.extend!(seconds)
      end

      # Something to run at the top of every tick, on the loop thread, where
      # {#running} may be read and changed safely: the live run applies the
      # page's commands here.
      #
      # @yieldparam dispatcher [OpenLanes::Engine::Dispatcher]
      # @return [void]
      def before_tick(&hook) = @before_tick << hook

      # @param key [String] a row's key, `"<ordinal>/<agent>"`
      # @return [OpenLanes::Engine::Dispatcher::Job, nil]
      def job(key) = @running.find { |j| j.key == key }

      # One control word into one running agent's control file.
      #
      # @param key [String]
      # @param word [String] one of {Execution::Control}'s words
      # @return [Boolean] whether there was a running agent to tell
      def signal(key, word)
        control = job(key)&.handle&.control or return false
        Execution::Control.write(control, word)
        true
      end

      # Stop the agent with a resume note and give it its round back, so it
      # is started again, on whatever model is now preferred, as soon as it
      # has stopped. The agent is told INTERRUPT, which is the word that
      # makes it leave the note.
      #
      # @param key [String]
      # @return [Boolean] whether there was a running agent to restart
      def requeue(key)
        signal(key, Execution::Control::INTERRUPT) or return false
        @requeued |= [key]
        true
      end

      # Compact one running agent's session and carry it on (W28): stopped
      # with INTERRUPT, its session compacted with `--resume`, then resumed
      # under the same handle, so the board shows one car carrying on. The
      # executor does the work, on the agent's own thread.
      #
      # @param key [String]
      # @param model [String, nil] what the session carries on in; nil keeps
      #   the model it was on
      # @return [OpenLanes::Execution::Executor::Compaction, nil] answered once
      #   the continuation has started; nil when nothing by that key is running
      def compact(key, model: nil) = job(key)&.handle&.compact!(model:)

      # The CLI a running agent was started on, which is what decides whether
      # its session can be resumed.
      #
      # @param job [OpenLanes::Engine::Dispatcher::Job]
      # @return [OpenLanes::Adapters::Base]
      def adapter_for(job)
        executor = @runner.executor
        agent = job.task.agent
        return Adapters.for(agent.adapter) unless executor.respond_to?(:profile_for)

        executor.profile_for(agent, job.task.subject).adapter
      end

      # Hand back the round an interrupted agent lost, so a person's "resume"
      # starts it again even when it had no rounds left.
      #
      # @param ordinal [#to_s]
      # @param agent [String]
      # @return [Boolean] whether there was an interrupted round to hand back
      def resume(ordinal, agent)
        @mutex.synchronize do
          entries = @history[[ordinal.to_s, agent.to_s]]
          last = entries.rindex { |h| h[:status] == "Interrupted" } or next false
          entries.delete_at(last)
          true
        end
      end

      # The model one agent gets on one plan from its next invocation (W24).
      #
      # @param ordinal [#to_s]
      # @param agent [String]
      # @param model [String, nil] nil forgets the choice
      # @return [Boolean] whether the executor can honour it
      def prefer_model(ordinal, agent, model)
        executor = @runner.executor
        return false unless executor.respond_to?(:prefer_model)

        executor.prefer_model(ordinal, agent, model)
        @models&.delete([ordinal.to_s, agent.to_s])
        true
      end

      # Throw a plan's work away (W9): every agent on it is stopped, each with
      # {KILL_GRACE} seconds to finish the line it is writing, and once the
      # last is gone the plan's worktree is reset and its folder sent back
      # one state. Plan-wide, because a pair shares one worktree and a reset
      # takes both halves. What can be refused is refused here, before any
      # agent is stopped.
      #
      # @param ordinal [#to_s]
      # @return [OpenLanes::Engine::Dispatcher::Discard] finished on a later tick
      # @raise [OpenLanes::Error] with the reason it cannot be done
      def discard(ordinal)
        ordinal = ordinal.to_s
        return @discarding[ordinal] if @discarding.key?(ordinal)

        if !@runner.isolated? || @runner.dry_run?
          raise OpenLanes::Error,
            "discard resets the plan's own worktree, and this run has none: under --isolation shared " \
            "or a dry run every agent works in the main checkout, which a reset would wipe. " \
            "Use stop on each agent instead."
        end
        subject = fresh_by(Plans::Ordinal.parse(ordinal)) or raise OpenLanes::Error, "there is no plan #{ordinal}"
        refusal = subject.machine.retreat_refusal and raise OpenLanes::Error, "#{ordinal} cannot go back: #{refusal}"

        @running.select { plan_of(it) == ordinal }.each do |job|
          Thread.new { job.handle.kill!(grace: KILL_GRACE, reason: :discard) }
        end
        @discarding[ordinal] = Discard.new(ordinal:)
      end

      # Plans whose claim another machine now holds (W26): their agents are
      # stopped, each with {KILL_GRACE} seconds, the plans leave this run,
      # and nothing this node does afterwards signs or renames for them.
      #
      # @param ordinals [Array<String>]
      # @return [void]
      def fence(ordinals)
        ordinals.map(&:to_s).each do |ordinal|
          @fenced |= [ordinal]
          @runner.drop_plan(ordinal)
          @running.select { plan_of(it) == ordinal }.each do |job|
            UI.log("claim lost; stopping", level: :warn, **job.task.log_fields)
            Thread.new { job.handle.kill!(grace: KILL_GRACE, reason: :fenced) }
          end
        end
      end

      # @return [OpenLanes::Engine::Board]
      def board
        up = @attempts.sum(&:up) + @running.sum { |j| j.up.to_i }
        down = @attempts.sum(&:down) + @running.sum { |j| j.down.to_i }
        Board.new(started_at: @started_at,
          status: run_status,
          plans: (@running.map { |j| j.task.subject.feature.ordinal.to_s } + @recent.map { |r| r[:row].ordinal } +
                  waiting).uniq,
          up:,
          down:,
          rows: rows,
          root: @runner.root,
          running: @running.size,
          live_up: @running.sum { |j| j.up.to_i },
          live_down: @running.sum { |j| j.down.to_i },
          waiting_on: @waiting_on.dup)
      end

      private

      # @return [Symbol]
      def run_status
        return :quitting if Execution::Control.quit?
        return :wrapping_up if @running.any? { |j| %i[wrap_up stopped].include?(j.handle.phase) }
        return :idle if @idle && quiet?

        :running
      end

      # @return [Array<OpenLanes::Engine::Board::Row>]
      def rows
        now = UI.monotonic
        @recent.reject! { |r| now - r[:at] > LINGER }
        @running.map { |job| row_for(job) } + @recent.map { |r| r[:row] }
      end

      # @param job [OpenLanes::Engine::Dispatcher::Job]
      # @return [String] the plan's ordinal
      def plan_of(job) = job.task.subject.feature.ordinal.to_s

      # Plans no agent may be started on and no rename may touch: one being
      # discarded or drained, one another machine holds (W26), and one whose
      # `locked-by.pid` another run wrote.
      #
      # @return [Array<String>]
      def untouchable
        busy = @running.map { plan_of(it) } + @discarding.keys + @unblocking.map(&:ordinal)
        busy + @runner.tree.subjects.select { @runner.foreign?(it) || locked_elsewhere?(it) }.map { it.feature.ordinal.to_s }
      end

      # The Redis claim covers machines that share one; the lock file covers
      # a second run on this machine, or one that never reached Redis.
      # Without this check such a run renamed the folder at start, wrote its
      # own lock over the holder's, and deleted it when its agent finished.
      # This run's own lock is not a reason to stay out: a pair shares it.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean]
      def locked_elsewhere?(subject) = Plans::Lock.read(subject.feature.path)&.held_elsewhere? || false

      # ---- pull requests a person owes (M4) ---------------------------------

      # The `gh` call runs on a thread of its own, so a slow GitHub never
      # stretches the one-second tick; its outcomes are applied on the first
      # tick after it returns, here, where every other rename happens.
      #
      # @return [void]
      def watch_pull_requests
        return unless @watch

        if @watching && !@watching.alive?
          settle_watch(@watching.value)
          @watching = nil
        end
        return if @watching || !@watch.due?

        subjects = @runner.in_scope.reject { untouchable.include?(it.feature.ordinal.to_s) }
        @watching = Thread.new do
          @watch.poll(subjects)
        # StandardError, not only OpenLanes::Error: `#value` re-raises whatever
        # ended the thread, so a stray JSON::ParserError or Errno from `gh`
        # would otherwise end the whole run on the next tick.
        rescue StandardError => e
          UI.log("pull requests unwatched this time: #{e.message.lines.first.to_s.strip}", level: :warn)
          nil
        end
      end

      # @param outcomes [Array<OpenLanes::Engine::PrWatch::Outcome>, nil] nil when the poll failed
      # @return [void]
      def settle_watch(outcomes)
        return if outcomes.nil?

        @waiting_on = outcomes.select { it.kind == :waiting }.group_by(&:plan).transform_values { it.map(&:pr) }
        # Every agent defined, not this run's roster: the mail waits in the
        # plan folder for whichever run next starts the builders, and a run
        # typed with `--agent hansolo-reviewer` must not lose it.
        effects = PrOutcomes.new(tree_dir: @runner.tree.dir, agents: Agents::Registry.new(dir: @runner.agents.dir))
        outcomes.each do |outcome|
          next if outcome.kind == :waiting || untouchable.include?(outcome.plan)

          applied = effects.apply(outcome) or next
          @finished_plans.delete(applied.plan) if applied.to
          UI.log("#{applied.plan}: #{applied.note}#{" → #{Plans::STATUS_BY_KEY.fetch(applied.to)}" if applied.to}")
          wake!
        end
        @state&.waiting_on = @waiting_on
      end

      # ---- discarding -------------------------------------------------------

      # Discards whose agents have all gone: the worktree is reset and the
      # folder moved back. A finished one stays one tick, for
      # {Live::Commands} to reply from, and is dropped on the next.
      #
      # @return [void]
      def finish_discards
        @discarding.delete_if { |_, discard| discard.finished? }
        @discarding.each_value do |discard|
          next if @running.any? { plan_of(it) == discard.ordinal }

          discard.status, discard.reason = throw_back(discard.ordinal)
        end
      end

      # @param ordinal [String]
      # @return [Array(String, String)] status and reason
      def throw_back(ordinal)
        subject = fresh_by(Plans::Ordinal.parse(ordinal)) or return ["refused", "#{ordinal}'s folder vanished"]
        reset = @runner.worktree.reset(subject.feature)
        from = subject.status
        to = subject.machine.retreat!
        @finished_plans.delete(ordinal)
        UI.log("discarded: #{from} -> #{to}", plan: ordinal)
        ["done", "#{ordinal} #{reset ? "reset" : "had no worktree to reset"}, and went back from #{from} to #{to}"]
      rescue OpenLanes::Error => e
        ["refused", "#{ordinal}'s agents were stopped, but: #{e.message}"]
      end

      # ---- unblocking -------------------------------------------------------

      # A blocked plan whose questions are all answered goes to the agent
      # that handles its state, the way `openlanes unblock` hands it over
      # (W10): the page's answer is what a person typing that command used
      # to be. Each answer set is tried once; a failed drain waits for
      # `blocked.md` to change. Drains finished since the last tick are
      # settled first, so the plan is picked up again in this run.
      #
      # @return [void]
      def unblock_answered
        @unblocking.reject { it.thread.alive? }.each { settle_unblock(it) }
        return if @runner.dry_run? || Execution::Control.quit?

        blocked = @runner.in_scope.select { BLOCKED.include?(it.status.key) }
        return if blocked.empty?

        busy = untouchable
        blocked.each do |subject|
          ordinal = subject.feature.ordinal.to_s
          next if busy.include?(ordinal)

          questions = Lifecycle::Unblocker.questions(subject)
          next if questions.empty? || !questions.all?(&:answered)

          answers = subject.read("blocked.md")
          next if @unblock_tried[ordinal] == answers

          # The drainer advances nothing itself, so {Registry#for_status},
          # which offers only agents that move a plan on, never names it.
          agent = @runner.agents.all.find { it.handles?(subject.status) } or next
          next unless @runner.claim(subject)

          @unblock_tried[ordinal] = answers
          start_unblock(agent, subject)
        end
      end

      # Prose questions go to the model off the tick thread; what it wrote
      # comes back on a later tick (D9). A quitting or dry run applies what
      # already came back and sends nothing new.
      #
      # @return [void]
      def convert_questions
        @conversions.call(busy: untouchable, start: !(@runner.dry_run? || Execution::Control.quit?))
      end

      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [void]
      def start_unblock(agent, subject)
        unblocker = Lifecycle::Unblocker.new(tree: Plans::Tree.new(dir: @runner.tree.dir),
          agent:,
          executor: @runner.executor,
          commit: true)
        UI.log("unblocking: every question answered", plan: subject.feature.ordinal.to_s, agent: agent.name)
        unblock = Unblock.new(ordinal: subject.feature.ordinal.to_s)
        unblock.thread = Thread.new do
          Thread.current.report_on_exception = false
          unblock.outcome = begin
            unblocker.drain(subject)
          rescue StandardError => e
            e
          end
        end
        @unblocking << unblock
      end

      # A drained plan's agents get their rounds back: a block is a question,
      # not the agent running out of turns.
      #
      # @param unblock [OpenLanes::Engine::Dispatcher::Unblock]
      # @return [void]
      def settle_unblock(unblock)
        @unblocking.delete(unblock)
        outcome = unblock.outcome
        if outcome.is_a?(Exception) || !outcome.ok
          note = outcome.is_a?(Exception) ? outcome.message : outcome.note
          return UI.log("unblock failed: #{note}", level: :warn, plan: unblock.ordinal)
        end

        @mutex.synchronize do
          @history.each { |(ordinal, _), entries| entries.reject! { it[:status] == "Blocked" } if ordinal == unblock.ordinal }
        end
        @finished_plans.delete(unblock.ordinal)
        wake!
        UI.log(outcome.cleared? ? "unblocked: blocked.md retired" : "unblock folded #{outcome.folded.size}",
          plan: unblock.ordinal)
      end

      # @param job [OpenLanes::Engine::Dispatcher::Job]
      # @return [OpenLanes::Engine::Board::Row]
      def row_for(job)
        task = job.task
        job.frame = job.frame.to_i + 1
        Board::Row.new(key: job.key,
          at: Time.now,
          ordinal: task.subject.feature.ordinal.to_s,
          file: job.file || task.agent.ledger.first.to_s,
          agent: task.agent.name,
          role: task.agent.role,
          round: task.round,
          rounds: rounds_for(task.agent),
          model: model_for(task.agent, task.subject),
          remaining: job.handle.remaining,
          phase: job.handle.phase,
          up: job.up.to_i,
          down: job.down.to_i,
          message: job.message,
          state: :running,
          pr: pr_for(task),
          frame: job.frame,
          elapsed: (UI.monotonic - job.started_at).round,
          subagents: job.subagents.to_i,
          history: job.history || [],
          context: job.context,
          since: job.started_at,
          session: job.handle.session,
          unacked: Board::Row.unacked_in(task.subject.feature.path),
          running: job.running || [])
      end

      # @param task [OpenLanes::Engine::Runner::Task]
      # @return [Hash, nil]
      def pr_for(task)
        return nil unless task.agent.ledger.include?("pull-requests.md")

        subject = Plans::Tree.new(dir: @runner.tree.dir).find(task.subject.feature.ordinal) or return nil
        pull = subject.pull_requests.find(&:open?) or return nil
        { number: pull.number, url: pull.url, rejected: subject.status.key == :rejected }
      end

      # @param agent [OpenLanes::Agents::Agent]
      # @return [Integer]
      def rounds_for(agent) = [agent.rounds, @rounds_cap].compact.min

      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject, nil] whose spec.md may override it
      # @return [String]
      def model_for(agent, subject = nil)
        executor = @runner.executor
        unless subject && executor.respond_to?(:profile_for)
          return (executor.respond_to?(:model) && executor.model) || agent.model || "default"
        end

        # Asked on every frame of the board, so spec.md is read once per plan
        # and agent rather than once per frame.
        (@models ||= {})[[subject.feature.ordinal.to_s, agent.name]] ||= executor.profile_for(agent, subject).label
      end

      # ---- starting ---------------------------------------------------------

      # Started stages a dead run left behind get the harness's own line and a
      # place in history, so eligibility treats them as an Interrupted round.
      #
      # Two records can say a stage was stranded: the run's own state file,
      # and the plan's `state.json`. The second is what survives a run whose
      # state file was lost, or a plan carried to another checkout. A stage
      # either names is resumed once.
      #
      # @return [void]
      def resume_stranded
        resumed = []
        if @state
          @state.load
          @state.stranded.each do |ordinal, stage|
            subject = @runner.tree.reload.find(Plans::Ordinal.parse(ordinal)) or next
            next if @runner.foreign?(subject)

            resumed << interrupt_stranded(subject, stage["agent"], stage["round"])
          end
        end
        unless @runner.dry_run?
          @runner.in_scope.reject { @runner.foreign?(it) }.each do |subject|
            Plans::PlanState.for(subject.feature.path).stranded.each do |stage|
              next if resumed.include?([subject.feature.ordinal.to_s, stage["agent"], stage["round"]])

              resumed << interrupt_stranded(subject, stage["agent"], stage["round"])
            end
          end
        end
        @state&.begin_run!(root: @runner.root)
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @param name [String] the agent
      # @param round [Integer]
      # @return [Array(String, String, Integer), nil] what was resumed
      def interrupt_stranded(subject, name, round)
        agent = @runner.agents.find(name) or return nil
        ordinal = subject.feature.ordinal.to_s
        harness_resume(subject, agent, round, "harness died")
        write_interrupted(subject, agent, round, "harness died")
        remember(ordinal, agent.name, subject.status.key, "Interrupted", round)
        @state&.record(ordinal, agent: agent.name, round:, status: "Interrupted", exit: "harness died")
        stage!(subject, agent, round, status: "Interrupted", note: "harness died", finished_at: Time.now.iso8601)
        [ordinal, agent.name, round]
      end

      # @return [void]
      def dispatch
        started = 0
        while @running.size < @runner.jobs && (pair = next_dispatchable)
          # Lost to another machine between the check and the claim: the next
          # pass sees the plan as foreign and steps around it.
          next unless @runner.claim(pair.last)

          # Lost the lock file to another run on this machine: the next tick
          # reads its lock and steps around the plan.
          break unless start(*pair)

          started += 1
        end
        settle_idle(started) if @stay
      end

      # ---- staying ----------------------------------------------------------

      # Nothing running, draining or being thrown back.
      #
      # @return [Boolean]
      def quiet? = @running.empty? && @unblocking.empty? && @discarding.empty?

      # Whether an idle staying run skips this tick's dispatch. Dispatching
      # reloads the tree and runs `resync dirs` over it, which is cheap once
      # but not once a second for hours with nothing to find, so an idle run
      # looks again every {RESCAN} ticks, or at once when woken. Commands,
      # drains and the board still run every tick; only the scan waits.
      #
      # @return [Boolean]
      def resting?
        return false unless @stay && @idle && quiet?

        @idle_ticks += 1
        return true unless @wake || @idle_ticks >= @rescan

        @wake = false
        @idle_ticks = 0
        false
      end

      # After a dispatch that started nobody: idle when nothing else is under
      # way, and said once per change, so the log reads as a story rather
      # than a heartbeat.
      #
      # @param started [Integer] agents this dispatch started
      # @return [void]
      def settle_idle(started)
        @idle = started.zero? && quiet?
        subjects = @runner.in_scope
        said = @idle ? idle_reason(subjects) : nil
        UI.log(said) if said && said != @said
        @said = said
      end

      # @param subjects [Array<OpenLanes::Plans::Subject>] the plans in scope
      # @return [String] what an idle run is waiting for
      def idle_reason(subjects)
        # Finished plans move into archive/ (N3), so an empty top level after
        # a run that shipped everything is "finished", not "no plans yet".
        if subjects.empty? && @runner.tree.everything.reload.subjects.empty?
          return "idle: no plans yet; create one from the page or with openlanes create"
        end
        if subjects.all? { FINISHED.include?(it.status.key) }
          return "idle: every plan is finished; create the next one from the page"
        end

        bombs = @runner.halted_by.map { it.feature.ordinal.to_s }
        return "idle: halted by 💣 #{bombs.join(", ")}; answer, or resume anyway from the page" unless bombs.empty?

        blocked = waiting
        return "idle: waiting for answers on #{blocked.join(", ")}" unless blocked.empty?

        held = @runner.held(@runner.dependencies(except: untouchable))
        return "idle: held by dependencies: #{held.map { |o, why| "#{o} #{why}" }.join("; ")}" unless held.empty?

        "idle: nothing to do"
      end

      # Blocked plans in scope that this machine may answer for: on the board
      # whether or not an agent touched them this run, so their questions
      # reach the page from the moment the run starts.
      #
      # @return [Array<String>] ordinals
      def waiting
        @runner.blocked.reject { @runner.foreign?(it) }.map { it.feature.ordinal.to_s }
      end

      # The next agent and plan to start, honouring a `next:` an agent wrote
      # over definition order.
      #
      # @return [Array(OpenLanes::Agents::Agent, OpenLanes::Plans::Subject), nil]
      def next_dispatchable
        reconcile
        # A 💣 stops new work, not work under way: agents already running
        # finish, and their plans settle, while nothing else starts.
        return nil if @runner.halted?

        @dependencies = @runner.dependencies(except: untouchable)
        blockers_first(@runner.in_scope).each do |subject|
          working = @running.select { plan_of(it) == subject.feature.ordinal.to_s }.map { it.task.agent }
          # After {#reconcile} this is the folder's name. On a dry run, which
          # renames nothing, it is what the name would have become. A plan an
          # agent is in right now is never reconciled, so its contents are
          # not asked: see {#partners_only}.
          state = working.empty? ? @runner.effective_status(subject) : subject.status
          next if Plans::StateMachine::SETTLED.include?(state.key)
          next if @finished_plans.include?(subject.feature.ordinal.to_s)
          next if @runner.foreign?(subject) || @discarding.key?(subject.feature.ordinal.to_s)
          next if held?(subject)
          next if locked_elsewhere?(subject)
          # A stopped rebase holds the checkout until the harness has
          # continued or aborted it; a partner started now would build on
          # conflict markers.
          next if @running.any? { plan_of(it) == subject.feature.ordinal.to_s && it.rebase }

          candidates = partners_only(Agents::Routing.filter(@runner.agents.for_status(state), subject), working, state)
          preferred = @preferred[subject.feature.ordinal.to_s]
          candidates = candidates.sort_by { |a| a.name == preferred ? 0 : 1 } if preferred
          agent = candidates.find { |a| eligible?(a, subject) }
          return [agent, subject] if agent
        end
        nil
      end

      # The dependency gate: a plan whose `depends_on:` names anything not yet
      # ✅, or which sits on a cycle, is not started this tick. Kept out of
      # {#next_dispatchable} so the rule can be read, and changed, alone.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean]
      def held?(subject) = !@dependencies.reason(subject.feature.ordinal).nil?

      # Plans that others wait for go first, so the work that unblocks the
      # most is started soonest. Stable: plans nobody waits for keep the
      # tree's order among themselves, and so do the blockers.
      #
      # @param subjects [Array<OpenLanes::Plans::Subject>]
      # @return [Array<OpenLanes::Plans::Subject>]
      def blockers_first(subjects)
        deps = @dependencies || @runner.dependencies
        subjects.each_with_index.sort_by { |s, i| [deps.blocks_of(s.feature.ordinal).empty? ? 1 : 0, i] }.map(&:first)
      end

      # One agent at a time on a plan, except a pair working the same state.
      #
      # A plan with an agent in it is judged by its folder's name, never by
      # what its contents would justify. Asking the contents is how the
      # minesweeper trial ran its whole chain inside ⚪ New: leah wrote her
      # `## Research` chapter, the next tick saw a Researched plan and started
      # yoda beside her, and leah's own Completed then found a partner running
      # and held the folder where it was. Every later agent repeated it, so
      # the folder never moved and luke and rey were building on a plan whose
      # name still said nobody had researched it.
      #
      # @param candidates [Array<OpenLanes::Agents::Agent>]
      # @param working [Array<OpenLanes::Agents::Agent>] already on the plan
      # @param state [OpenLanes::Plans::Status] the folder's state
      # @return [Array<OpenLanes::Agents::Agent>]
      def partners_only(candidates, working, state)
        return candidates if working.empty?

        team = @runner.agents.team_for(state).map(&:name)
        return [] unless working.all? { team.include?(it.name) }

        candidates.select { team.include?(it.name) }
      end

      # A folder's name can lag its contents: a run killed before its rename,
      # a plan.md written by hand, a resync nobody ran. So the names are
      # reconciled before every dispatch, the way `resync dirs` would, and a
      # ⚪ folder that already holds a plan goes to the pair under its honest
      # name rather than to leah-researcher under its stale one. Plans an
      # agent is working in right now are left alone: the prompt names the
      # folder by path, and moving it under a running agent would strand
      # every write it makes afterwards. Nor is a plan another machine holds
      # touched: its name is that machine's to change. Then the blocked plans
      # age (plan 009), so a 💣 is in place before anyone is assigned.
      #
      # @return [void]
      def reconcile
        busy = untouchable
        Lifecycle::Resync::Dirs.new(tree: @runner.tree.reload, except: busy).call(commit: !@runner.dry_run?)
        fast_forward(busy) unless @runner.dry_run?
        @runner.age!(except: busy)
      end

      # Plans whose lane skips research, rewriting or planning are moved past
      # those phases before anyone is assigned, so the first agent they meet
      # is the one their lane starts with.
      #
      # @param busy [Array<String>] ordinals an agent is working right now
      # @return [void]
      def fast_forward(busy)
        @runner.in_scope.each do |subject|
          next if busy.include?(subject.feature.ordinal.to_s)

          moved = Lifecycle::Lanes.advance(subject, commit: true) or next
          UI.log("lane: #{moved.first} -> #{moved.last}", plan: subject.feature.ordinal.to_s)
        end
      end

      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean]
      def eligible?(agent, subject)
        ordinal = subject.feature.ordinal.to_s
        return false if @running.any? { |j| j.task.agent.name == agent.name && j.task.subject.feature.ordinal.to_s == ordinal }

        past = @history[[ordinal, agent.name]].select { |h| h[:state] == subject.status.key }
        return true if past.empty?
        return false if %w[Completed Blocked].include?(past.last[:status])

        past.size < rounds_for(agent)
      end

      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean] false when another run took the plan's lock first
      def start(agent, subject)
        ordinal = subject.feature.ordinal.to_s
        round = @history[[ordinal, agent.name]].count { |h| h[:state] == subject.status.key } + 1
        from = subject.status.key
        subject = rename_on_start(subject, agent) unless @runner.dry_run?
        # The lock says the folder is in use, so nothing renames it while the
        # agent holds its path. It is taken before anything is recorded as
        # started, since another run can win it between the check and here,
        # and before the thread, so the next tick already sees it; it goes
        # when the last agent in the plan does, however that agent went.
        return false unless lock(ordinal, subject)

        release_owed = true
        # A checkout another agent is working in is never moved under it.
        alone = @running.none? { plan_of(it) == ordinal }
        task = @runner.prepare(agent, subject, round, refresh: alone, hold: rebases.hold(ordinal))
        handle = Execution::Executor::Handle.new
        job = Job.new(key: "#{ordinal}/#{agent.name}",
          task:,
          handle:,
          started_at: UI.monotonic,
          from:,
          state: subject.status.key,
          up: 0,
          down: 0,
          subagents: 0,
          frame: 0)
        if task.refresh&.conflicted?
          start_rebase(job, ordinal)
          release_owed = false
          return true
        end
        job.message = task.refresh.summary if task.refresh&.kind == :pending
        if agent.advances_to && Plans::STATUS_BY_KEY.key?(agent.advances_to)
          successor = Agents::Routing.filter(@runner.agents.for_status(Plans::STATUS_BY_KEY.fetch(agent.advances_to)),
            subject).first&.name
        end
        # Each member of a pair is told who the others are, so the executor
        # can name them beside the plan's mailbox. A partner routing would
        # never start is not a partner.
        team = @runner.agents.team_for(Lifecycle::Resync::Dirs.target(subject))
        partners = Agents::Routing.filter(team, subject) - [agent]
        remember(ordinal, agent.name, job.state, "Started", round)
        stage!(subject,
          agent,
          round,
          status:     "Started",
          from:       from.to_s,
          started_at: Time.now.iso8601,
          run:        { pid: Process.pid, host: Socket.gethostname },
          **profile_fields(agent, subject))
        @state&.record(ordinal,
          agent:      agent.name,
          round:,
          status:     "Started",
          state:      from.to_s,
          model:      model_for(agent, subject),
          file:       agent.ledger.first,
          started_at: Time.now.iso8601)
        UI.log("started", **task.log_fields)
        job.thread = Thread.new do
          Thread.current.report_on_exception = false
          job.result = begin
            @runner.executor.call(agent, subject, root: task.root, round:, successor:, handle:, partners:) { |progress|
              job.up = progress.up
              job.down = progress.down
              job.subagents = progress.subagents
              job.running = progress.running
              job.context = progress.context
              job.message = progress.message || progress.activity
              job.history = Board::Row.remember(job.history || [], job.message)
            }
          rescue StandardError => e
            e
          ensure
            @locks.release(ordinal) unless @runner.dry_run?
          end
        end
        release_owed = false
        @running << job
        true
      rescue StandardError
        # Failed before the thread that releases it existed.
        @locks.release(ordinal) if release_owed && !@runner.dry_run?
        raise
      end

      # A job that resolves a stopped rebase rather than working the plan
      # (D10). Nothing is signed or remembered for it: no round of the
      # agent's is spent, and plan work starts on the next tick, on the
      # rebased branch, or on the old one if the rebase was aborted.
      #
      # @param job [OpenLanes::Engine::Dispatcher::Job]
      # @param ordinal [String]
      # @return [void]
      def start_rebase(job, ordinal)
        stopped = job.task.refresh
        job.rebase = stopped
        job.message = "rebasing onto #{stopped.base}: #{stopped.files.size} conflicted file#{"s" unless stopped.files.size == 1}"
        UI.log("started rebase resolution", **job.task.log_fields)
        job.thread = Thread.new do
          Thread.current.report_on_exception = false
          job.result = begin
            rebases.resolve(job.task, handle: job.handle) { |progress|
              job.up = progress.up
              job.down = progress.down
              job.message = "rebasing: #{progress.message || progress.activity}"
              job.history = Board::Row.remember(job.history || [], job.message)
            }
          rescue StandardError => e
            e
          ensure
            @locks.release(ordinal)
          end
        end
        @running << job
      end

      # @param ordinal [String]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean] whether this run now holds the plan's lock
      def lock(ordinal, subject)
        @locks.hold(ordinal, subject.feature.path) unless @runner.dry_run?
        true
      rescue Plans::Lock::Held => e
        UI.log("lock lost: #{e.message}", level: :warn, plan: ordinal)
        false
      end

      # `starts_as`: the folder moves the moment the agent is dispatched, where
      # the topology allows, so luke's start is what makes a plan 🟡.
      #
      # @return [OpenLanes::Plans::Subject] fresh, under whichever name it now has
      def rename_on_start(subject, agent)
        target = agent.starts_as
        return subject unless target && subject.machine.may?(target)

        subject.machine.promote!(target)
        Plans::Tree.new(dir: @runner.tree.dir).find(subject.feature.ordinal) || subject
      end

      # ---- polling ----------------------------------------------------------

      # @return [void]
      def poll
        @running.each do |job|
          reading = read_ledger(job.task)
          entry = Plans::Ledger.last_for(reading, job.task.agent.name)
          job.file = entry&.file || job.file
          job.status = entry&.status
          @state&.record(job.task.subject.feature.ordinal.to_s,
            agent:  job.task.agent.name,
            round:  job.task.round,
            status: entry&.status || "Started",
            file:   job.file,
            up:     job.up,
            down:   job.down,
            pid:    job.handle.pid,
            **{ session: job.handle.session }.compact)
        end
      end

      # Messages published to Redis, kept in their plan's `state.json`
      # unless that file already has them. Every plan with an agent running
      # is drained, and so is every plan the stream has mail for, running or
      # not: a worktree's `mail send` reaches the main checkout only through
      # the stream, which forgets it after an hour. A plan stays on the list
      # until nothing of its mail is left pending.
      #
      # A message is acked once it is kept, or once it proves it never can
      # be (no body, no single sender), since retrying an invalid message
      # every second for an hour would only repeat the log line. One whose
      # plan this checkout cannot find stays pending and is tried next tick.
      #
      # Only delivery: nothing here reads whether a message was acked by its
      # reader, and no assignment turns on it (D3). Redis going away mid-run
      # costs the drain, never the tick.
      #
      # @return [void]
      def drain_mail
        return if @mail.nil? || @runner.dry_run?

        found, @mail_cursor = @mail.plans_since(@mail_cursor || "0")
        @mail_plans = (@mail_plans || Set.new) | found
        plans = @running.map { plan_of(it).to_s } | @mail_plans.to_a
        plans.each do |ordinal|
          pending = @mail.drain(plan: ordinal, consumer: "harness") { |message| keep_mail(ordinal, message) }
          @mail_plans.delete(ordinal) if pending.empty?
        end
      rescue Live::Unavailable, SystemCallError => e
        UI.log("mail not drained: #{e.message}", level: :warn)
      end

      # @param ordinal [String]
      # @param message [Hash]
      # @return [Boolean] whether the stream may forget it
      def keep_mail(ordinal, message)
        subject = fresh_by(ordinal) or return false
        Plans.mailbox(subject.feature.path).deliver(message)
        true
      rescue OpenLanes::Error => e
        UI.log("mail not kept: #{e.message}", level: :warn, plan: ordinal)
        true
      end

      # @param task [OpenLanes::Engine::Runner::Task]
      # @return [OpenLanes::Plans::Ledger::Reading]
      def read_ledger(task)
        subject = Plans::Tree.new(dir: @runner.tree.dir).find(task.subject.feature.ordinal) or return Plans::Ledger::Reading.empty
        Plans::Ledger.read(subject.feature.path, task.agent.ledger)
      end

      # ---- settling ---------------------------------------------------------

      # @return [void]
      def reap
        @running.select(&:finished?).each do |job|
          @running.delete(job)
          attempt = settle(job)
          # A requeue, or a compaction that stopped the agent and then could
          # not happen, hands the round back: the stop was a person's choice.
          requeued = @requeued.delete(job.key)
          forget_round(job) if requeued || job.handle.compaction&.restart
          @attempts << attempt
          row = row_for(job)
          @recent << { at: UI.monotonic, row: row.with(state: attempt.ok ? :done : :failed,
            message: attempt.note,
            history: Board::Row.remember(row.history, attempt.note),
            remaining: nil,
            phase: nil,
            running: [],
            bold: !attempt.ok) }
          # `to:` names the state the plan moved to, on the terminal and in the log.
          moved = Plans::STATUS_BY_KEY[attempt.to]&.to_s if attempt.advanced?
          UI.log(attempt.ok ? "finished: #{attempt.note}" : "failed: #{attempt.note}",
            level: attempt.ok ? :info : :warn,
            **job.task.log_fields,
            **{ to: moved }.compact)
        end
      end

      # @param job [OpenLanes::Engine::Dispatcher::Job]
      # @return [OpenLanes::Engine::Runner::Attempt]
      def settle(job)
        task = job.task
        agent = task.agent
        ordinal = task.subject.feature.ordinal.to_s
        result = job.result
        base = attempt_for(job)
        # Before anything reads the ledger: a resolution signs nothing, so
        # whatever the ledger holds is the plan's previous round, not this one.
        return base.with(ok: false, note: "rebase: #{result.message}") if job.rebase && result.is_a?(Exception)
        return base if job.rebase
        return crashed(job, base, result) if result.is_a?(Exception)
        return base.with(note: result.note) if @runner.dry_run?

        reading = read_ledger(task)
        entry = Plans::Ledger.last_for(reading, agent.name)
        entry = nil if entry && entry.round != task.round
        problems = reading.problems.map { |p| "#{p.file}:#{p.line} unreadable ledger line" }

        attempt = if (why = stopped_for(ordinal))
                    stopped_by_harness(job, base, why)
                  elsif result.killed || (result.ok && (entry.nil? || entry.status == "Started"))
                    verify_and_sign(job, base, reason_for(result))
                  elsif !result.ok
                    fresh(task)&.then { harness_resume(it, agent, task.round, result.note, phrase: job.message) }
                    remember(ordinal, agent.name, job.state, "Interrupted", task.round)
                    base.with(ok: false, note: result.note)
                  elsif entry.completed?
                    complete(job, base, entry, reading)
                  elsif entry.blocked?
                    park(job, base, entry)
                  else
                    remember(ordinal, agent.name, job.state, entry.status, task.round)
                    base.with(status: entry.status, note: retry_note(agent, entry))
                  end
        attempt = attempt.with(note: "#{attempt.note}; #{problems.join(", ")}") unless problems.empty?
        attempt = attempt.with(to: fresh(task)&.status&.key || attempt.to)
        # One outcome, written to both records. The engine's state file once
        # defaulted a failed round to Completed while state.json said
        # Interrupted, so the page and the plan disagreed about the same round.
        outcome = attempt.status || (attempt.ok ? "Completed" : "Interrupted")
        if (settled = fresh(task))
          stage!(settled,
            agent,
            task.round,
            status:      outcome,
            to:          attempt.to.to_s,
            finished_at: Time.now.iso8601,
            up:          attempt.up.to_i,
            down:        attempt.down.to_i,
            seconds:     attempt.seconds.to_f.round(1),
            note:        attempt.note.to_s)
        end
        @state&.record(ordinal,
          agent:    agent.name,
          round:    task.round,
          status:   outcome,
          exit:     attempt.ok ? "ok" : attempt.note,
          ended_at: Time.now.iso8601,
          up:       attempt.up,
          down:     attempt.down)
        attempt
      end

      # @param ordinal [String]
      # @return [String, nil] why the harness stopped the plan's agents, if it did
      def stopped_for(ordinal)
        return "claim lost to another machine" if @fenced.include?(ordinal)

        "discarded by a person" if @discarding.key?(ordinal)
      end

      # An agent stopped because its plan was discarded or taken by another
      # machine: what it left is about to be thrown away, or is no longer
      # this node's to judge, so the harness signs nothing for it.
      #
      # @return [OpenLanes::Engine::Runner::Attempt]
      def stopped_by_harness(job, base, why)
        task = job.task
        subject = fresh(task)
        if subject
          harness_resume(subject, task.agent, task.round, why, phrase: job.message)
          write_interrupted(subject, task.agent, task.round, why)
        end
        remember(plan_of(job), task.agent.name, job.state, "Interrupted", task.round)
        base.with(ok: false, status: "Interrupted", note: why)
      end

      # @param result [OpenLanes::Execution::Executor::Result]
      # @return [String]
      def reason_for(result)
        case result.killed
        when :key then "killed by harness after #{KILL_GRACE}s grace"
        when :timeout then "timed out, killed #{Execution::Clock::GRACE}s after STOP"
        when :quit then "interrupted, killed #{Execution::Control::GRACE}s after #{Execution::Control.interrupted? ? "ctrl-c" : "q"}"
        else Execution::Control.interrupted? ? "interrupted by ctrl-c" : "no closing ledger line"
        end
      end

      # @return [String]
      def retry_note(agent, entry)
        left = rounds_for(agent) - entry.round
        left.positive? ? "#{entry.status}; #{left} round#{"s" unless left == 1} left" : "#{entry.status}; no rounds left"
      end

      # The agent stopped without saying it finished. If the state it was
      # advancing to is justified by what is on disk, the work happened and
      # the harness signs for it, in bold, saying why it had to.
      #
      # @return [OpenLanes::Engine::Runner::Attempt]
      def verify_and_sign(job, base, reason)
        task = job.task
        agent = task.agent
        subject = fresh(task) or return base.with(ok: false, note: "plan folder vanished")
        # Read before the harness's own Interrupted line lands, which would
        # otherwise be the "last ledger line" the resume record quotes.
        last = last_line(subject, agent)
        write_interrupted(subject, agent, task.round, reason)
        target = agent.advances_to
        if target && subject.machine.may?(target)
          successor = @runner.agents.for_status(Plans::STATUS_BY_KEY.fetch(target)).first&.name
          lines = [Plans::Ledger.render(Plans::Ledger::Entry.new(at: Time.now,
            agent: agent.name,
            status: "Completed",
            round: task.round,
            note: "signed by harness: work verified on disk",
            file: "",
            line: 0))]
          lines << Plans::Ledger.render_handoff(Plans::Ledger::Handoff.new(at: Time.now, next: successor, file: "", line: 0)) if successor
          Plans::Ledger.append(File.join(subject.feature.path, agent.ledger.first), *lines)
          entry = Plans::Ledger.last_for(read_ledger(task), agent.name)
          complete(job, base.with(note: "#{reason}; signed by harness"), entry, read_ledger(task))
        else
          harness_resume(subject, agent, task.round, reason, last:, phrase: job.message)
          remember(subject.feature.ordinal.to_s, agent.name, job.state, "Interrupted", task.round)
          base.with(ok: false, status: "Interrupted", note: "#{reason}; #{retry_note(agent, Plans::Ledger::Entry.new(at: Time.now, agent: agent.name, status: "Interrupted", round: task.round, file: "", line: 0))}")
        end
      end

      # The resume record the agent did not leave: killed when its grace ran
      # out, dead, or stopped by the harness. Only what the harness saw, its
      # last ledger line and its last transcript phrase, because that is all
      # it knows; an agent's own record of this round or a later one stays,
      # which {Plans::LastKnownState#supersedes?} decides under the plan lock.
      # Pids, tokens and exit codes stay in `openlanes-state.json`.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param agent [OpenLanes::Agents::Agent]
      # @param round [Integer]
      # @param reason [String] why the agent stopped
      # @param last [OpenLanes::Plans::Ledger::Entry, nil] read before the
      #   harness wrote its own Interrupted line
      # @param phrase [String, nil] the transcript's last phrase
      # @return [void]
      def harness_resume(subject, agent, round, reason, last: last_line(subject, agent), phrase: nil)
        return if @runner.dry_run?

        seen = "last ledger line: #{last.status}, round #{last.round}#{": #{last.note}" if last.note}" if last
        note = [reason, seen, ("last seen: #{phrase}" if phrase && !phrase.empty?)].compact.join("; ")
        entry = Plans::LastKnownState.new(source: "harness", round:, status: "Interrupted", note:)
        Plans::PlanState.for(subject.feature.path).record_last_known(agent.name, entry)
      rescue SystemCallError, OpenLanes::Error => e
        UI.log("resume record not written: #{e.message}", level: :warn, plan: subject.feature.ordinal.to_s)
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @param agent [OpenLanes::Agents::Agent]
      # @return [OpenLanes::Plans::Ledger::Entry, nil]
      def last_line(subject, agent) = Plans::Ledger.last_for(Plans::Ledger.read(subject.feature.path, agent.ledger), agent.name)

      # @return [void]
      def write_interrupted(subject, agent, round, reason)
        line = Plans::Ledger.render(Plans::Ledger::Entry.new(at: Time.now,
          agent: agent.name,
          status: "Interrupted",
          round:,
          note: reason,
          file: "",
          line: 0,
          bold: true))
        Plans::Ledger.append(File.join(subject.feature.path, agent.ledger.first), line)
      end

      # A Completed entry: publish if the move is to 🟢, then move the folder,
      # and honour the `next:` line.
      #
      # @return [OpenLanes::Engine::Runner::Attempt]
      def complete(job, base, entry, reading)
        task = job.task
        agent = task.agent
        ordinal = task.subject.feature.ordinal.to_s
        subject = fresh(task) or return base.with(ok: false, note: "plan folder vanished")
        remember(ordinal, agent.name, job.state, "Completed", task.round)
        Lifecycle::Completion.copy(subject) if agent.ledger.include?("plan.md")
        # Only a reviewer rules. A builder that signed `Completed (approved)`
        # once had its own work taken as approved: the plan was parked as
        # finished at 🟡, never reviewed and never published.
        verdict = verdict_of(entry) if agent.phase.to_s == REVIEW_PHASE
        partner_running = @running.any? { |j| j.task.subject.feature.ordinal.to_s == ordinal }
        target = target_for(agent, verdict, partner_running)

        if verdict == :approved
          @finished_plans << ordinal
          return base.with(status: "Completed", note: "#{base.note}; approved, awaiting merge")
        end

        attempt = base.with(status: "Completed")
        return built_locally(attempt, ordinal) if local_only_review?(target, subject)

        if target
          attempt = attempt.with(note: "#{base.note}#{" (#{entry.note})" if entry.note}")
          published = publish_for_review(task, target, subject, attempt)
          return unpublished(published, ordinal) if published.refused

          attempt = published.attempt
          subject = published.subject
          return unjustified(job, attempt, subject, target) unless subject.machine.may?(target)

          subject.machine.promote!(target)
          attempt = attempt.with(to: target)
        end

        handoff = Plans::Ledger.handoff_after(reading, entry)
        attempt = honour(handoff, subject, attempt) if handoff
        attempt
      end

      # The agent signed Completed, but what it left does not justify the
      # state it advances to. The folder stays, its `next:` is not honoured,
      # and the round is recorded as Interrupted, which is what the page
      # lists under Needs you once the agent's rounds run out. Taking the
      # signature at its word instead parked the plan: nobody else handles
      # the state it is still in, and its own agent counted itself done.
      #
      # @return [OpenLanes::Engine::Runner::Attempt]
      def unjustified(job, attempt, subject, target)
        status = Plans::STATUS_BY_KEY.fetch(target)
        remember(plan_of(job), job.task.agent.name, job.state, "Interrupted", job.task.round)
        attempt.with(ok: false,
          status: "Interrupted",
          note: "ledger says Completed but #{status} is not justified: #{status.violation(subject)}")
      end

      # A build finished in a run that opens no pull request: 🟢 needs one,
      # so the folder cannot move, and failing the attempt would only start
      # the builder again on work that is done. Only the missing pull request
      # is forgiven, and pull-requests.md with it, where the pull request
      # would be recorded: a build that deleted another file 🟢 requires
      # (spec.md, plan.md) is still reported, rather than parked as done. 🟡's own
      # invariant is not asked, since a quick-lane plan.md has no work units.
      #
      # @param target [Symbol, nil]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean]
      def local_only_review?(target, subject)
        return false unless target == :ready_for_review && !@runner.publishes? && !subject.machine.may?(target)

        (Plans::STATUS_BY_KEY.fetch(target).requires - %w[pull-requests.md]).all? { subject.file?(it) }
      end

      # The build stays at 🟡, finished for this run, saying why.
      #
      # @param attempt [OpenLanes::Engine::Runner::Attempt]
      # @param ordinal [String]
      # @return [OpenLanes::Engine::Runner::Attempt]
      def built_locally(attempt, ordinal)
        @finished_plans << ordinal
        attempt.with(note: "#{attempt.note}; built locally, no pull request in this run, so it waits for one")
      end

      # @param entry [OpenLanes::Plans::Ledger::Entry]
      # @return [Symbol, nil] :rejected, :approved, :slop, :product or nil
      def verdict_of(entry)
        note = entry.note.to_s.downcase
        return :rejected if note.include?("reject")
        return :approved if note.include?("approv")
        return :slop if note.include?("slop") || note.include?("rewrite")
        return :product if note.include?("product")

        nil
      end

      # @return [Symbol, nil] where the folder goes
      def target_for(agent, verdict, partner_running)
        case verdict
        when :rejected then :rejected
        when :slop then :shit
        else partner_running ? agent.holds_at : agent.advances_to
        end
      end

      # Push the build and open, or update, its pull request, before the
      # folder is asked whether it may move to 🟢.
      #
      # The order is the whole point. 🟢 is justified by an open pull request
      # recorded in `pull-requests.md`, and only the publisher records one.
      # Promoting first and publishing after, as this once did, asked the
      # invariant a question only the publish could answer: every first build
      # under worktree isolation failed with "Ready for Review requires an open
      # pull request; none are recorded", and no plan ever reached review.
      #
      # This runs in settle, after the executor's own boundary check has
      # already compared HEAD against where the agent started. The commit and
      # push are the harness's, so they cannot be mistaken for the agent's.
      #
      # @param task [OpenLanes::Engine::Runner::Task]
      # @param target [Symbol]
      # @param subject [OpenLanes::Plans::Subject] the plan, read fresh
      # @param attempt [OpenLanes::Engine::Runner::Attempt]
      # @return [OpenLanes::Engine::Dispatcher::Published]
      def publish_for_review(task, target, subject, attempt)
        unchanged = Published.new(attempt:, subject:, refused: false)
        return unchanged unless target == :ready_for_review

        publication = @runner.publish(task, subject)
        if publication&.refusal
          Published.new(attempt: attempt.with(ok: false, note: "#{attempt.note}; publish refused: #{publication.refusal}"), subject:, refused: true)
        elsif publication&.published?
          verb = publication.updated ? "pushed to" : "opened"
          note = "#{attempt.note}; #{verb} #{publication.url}"
          note += "; #{Plans::ReviewLabel::INITIAL} not applied: #{publication.label_error}" if publication.label_error
          Published.new(attempt: attempt.with(note:), subject: fresh(task) || subject, refused: false)
        else
          unchanged
        end
      end

      # A refused publish leaves the plan where it was. Running the builder
      # again would redo finished work to hit the same rejected push, so the
      # plan is done for this run and the attempt says why.
      #
      # @param published [OpenLanes::Engine::Dispatcher::Published]
      # @param ordinal [String]
      # @return [OpenLanes::Engine::Runner::Attempt]
      def unpublished(published, ordinal)
        @finished_plans << ordinal
        published.attempt
      end

      # A `next:` that names someone who handles the plan's new state is
      # honoured by preferring them; one that does not is reported, and the
      # state's own agents take it, because a wrong name must not stall a plan.
      #
      # @return [OpenLanes::Engine::Runner::Attempt]
      def honour(handoff, subject, attempt)
        current = fresh_by(subject.feature.ordinal) || subject
        named = @runner.agents.find(handoff.next)
        if named&.handles?(current.status)
          @preferred[current.feature.ordinal.to_s] = named.name
          attempt
        else
          who = named ? "does not handle #{current.status}" : "is not an agent"
          attempt.with(note: "#{attempt.note}; next: names #{handoff.next}, who #{who}")
        end
      end

      # @return [OpenLanes::Engine::Runner::Attempt]
      def park(job, base, entry)
        task = job.task
        subject = fresh(task) or return base.with(ok: false, note: "plan folder vanished")
        remember(subject.feature.ordinal.to_s, task.agent.name, job.state, "Blocked", task.round)
        target = verdict_of(entry) == :product ? :product_blocked : :blocked
        if subject.machine.may?(target)
          subject.machine.promote!(target)
          base.with(to: target, status: "Blocked", note: "blocked; see blocked.md")
        else
          base.with(ok: false, status: "Blocked", note: "ledger says Blocked but #{Plans::STATUS_BY_KEY.fetch(target).violation(subject)}")
        end
      end

      # @return [OpenLanes::Engine::Runner::Attempt]
      def crashed(job, base, error)
        fresh(job.task)&.then { harness_resume(it, job.task.agent, base.round, error.message.lines.first.to_s.strip, phrase: job.message) }
        remember(base.ordinal, base.agent, job.state, "Interrupted", base.round)
        base.with(ok: false, note: error.message.lines.first.to_s.strip)
      end

      # @param job [OpenLanes::Engine::Dispatcher::Job]
      # @return [OpenLanes::Engine::Runner::Attempt]
      def attempt_for(job)
        task = job.task
        result = job.result
        spend = ->(field) { result.respond_to?(field) ? result.public_send(field) : 0 }
        Runner::Attempt.new(ordinal: task.subject.feature.ordinal.to_s,
          agent: task.agent.name,
          from: job.from,
          to: job.from,
          ok: result.respond_to?(:ok) ? !!result.ok : false,
          note: result.respond_to?(:note) ? result.note.to_s : "",
          up: spend.call(:up),
          down: spend.call(:down),
          subagents: spend.call(:subagents),
          delegated: spend.call(:delegated),
          seconds: spend.call(:seconds),
          round: task.round,
          file: job.file || task.agent.ledger.first.to_s,
          model: model_for(task.agent, task.subject),
          status: job.status)
      end

      # One round in the plan's own `state.json`. A dry run writes nothing, and
      # a harness that cannot write the file reports it and carries on: the
      # folder name and the ledger still say what happened.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param agent [OpenLanes::Agents::Agent]
      # @param round [Integer]
      # @return [void]
      def stage!(subject, agent, round, **fields)
        return if @runner.dry_run?

        Plans::PlanState.for(subject.feature.path).stage!(agent: agent.name, round:, **fields)
      rescue SystemCallError, OpenLanes::Error => e
        UI.log("state.json not written: #{e.message}", level: :warn, plan: subject.feature.ordinal.to_s)
      end

      # @return [Hash] adapter, model and effort, when the executor can say
      def profile_fields(agent, subject)
        executor = @runner.executor
        return {} unless executor.respond_to?(:profile_for)

        profile = executor.profile_for(agent, subject)
        { adapter: profile.adapter.name, model: profile.model, effort: profile.effort }
      end

      # @return [OpenLanes::Plans::Subject, nil] the plan read fresh from the main tree
      def fresh(task) = fresh_by(task.subject.feature.ordinal)

      # @return [OpenLanes::Plans::Subject, nil]
      def fresh_by(ordinal) = Plans::Tree.new(dir: @runner.tree.dir).find(ordinal)

      # One entry per round: the Started written at dispatch is overwritten by
      # the outcome rather than joined by it. Two entries a round would spend
      # an agent's rounds at double speed and number them 1, 3, 5.
      #
      # @return [void]
      def remember(ordinal, agent, state, status, round)
        @mutex.synchronize do
          entries = @history[[ordinal.to_s, agent]]
          entry = entries.find { |h| h[:state] == state && h[:round] == round }
          entry ? entry[:status] = status : entries << { state:, status:, round: }
        end
      end

      # A requeued agent's round is handed back: the stop was a person's
      # choice, not the agent running out of turns.
      #
      # @param job [OpenLanes::Engine::Dispatcher::Job]
      # @return [void]
      def forget_round(job)
        ordinal = job.task.subject.feature.ordinal.to_s
        @mutex.synchronize do
          @history[[ordinal, job.task.agent.name]].reject! { |h| h[:state] == job.state && h[:round] == job.task.round }
        end
        @finished_plans.delete(ordinal)
      end

      # @return [void]
      def persist
        return unless @state

        @state.heartbeat!
        @state.save
      end
    end
  end
end
