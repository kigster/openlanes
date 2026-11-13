# frozen_string_literal: true

require "forwardable"
require "monitor"

require "socket"

module OpenLanes
  module Engine
    # The loop. A tick every {TICK} seconds: reap what finished and settle it
    # against the ledger, poll what is running for its latest line, start what is
    # dispatchable, heartbeat the state file, hand the screen a board.
    #
    # Nothing here guesses. An agent that finished says so in its document;
    # the state machine says whether the folder may move; the state file says
    # what an earlier run left behind. When the three disagree the row goes
    # red with the reason, and nobody is re-run to paper over it.
    #
    # The loop itself only wires the steps and orders them: each part of a
    # tick is a {Step} under `dispatcher/`, working on the one {Desk} they
    # share. {Settle} reaps, {Poll} reads, {Assign} picks and {Start} sets
    # going, {Rename} moves the folder; {Lanes}, {Rulings} and {Rows} are
    # the commands, the off-thread results and the board.
    class Dispatcher
      extend Forwardable

      # Who the harness signs its own mail as.
      HARNESS = Recovery::HARNESS

      # States a plan waits in for a person's answer. An answered 💣 is
      # drained like an answered ⭕.
      BLOCKED = %i[blocked product_blocked bomb].freeze

      # How long a settled row stays on the screen.
      LINGER = 10

      # Seconds a kill waits between STOP and SIGKILL.
      KILL_GRACE = 15

      # Seconds between ticks. The spec promises the page sees an engine
      # change within a second, and the board crosses two waits to get there:
      # this one, then the event stream's wait for a nudge (or, without a
      # subscription, its {Web::Events::POLL} of 0.25 s). At one second a
      # tick, a rename just after one reached the page in up to 1.25 s; half
      # a second leaves the worst case near 0.75 s.
      TICK = 0.5

      # Seconds between rescans of the tree while a staying run has nothing
      # to do. A command from the page rescans at once; this interval is for
      # what arrives by other means: a folder edited by hand, `openlanes
      # create` typed in another terminal, a `blocked.md` answered in an editor.
      RESCAN_SECONDS = 5

      # {RESCAN_SECONDS} as ticks, which is what the idle count compares.
      RESCAN = (RESCAN_SECONDS / TICK).round

      # @param seconds [Integer] an interval as a person states it
      # @return [Integer] the same interval in ticks, at least one
      def self.ticks(seconds) = [(seconds / TICK).round, 1].max

      # Plans with nothing left to do, which an idle staying run reports
      # reaching rather than ending on. Not `Status#terminal?`:
      # only ❌ has no way out, while ✅ and 😎 can still roll back, and a
      # project whose plans all merged is finished in every sense a person
      # means. The page's backlog draws the same line.
      FINISHED = Live::Snapshot::FINISHED

      # The phase whose Completed notes are verdicts (approved, rejected,
      # slop). Anyone else's note is only a note.
      REVIEW_PHASE = "review"

      # Seconds between passes over the 🏁 plans' pull requests.
      MERGE_POLL = Steps::POLL

      # What of the {Desk} is also this loop's own public face: what the
      # page's commands, the live session and the run's report read.
      PUBLIC = %i[running runner attempts mail mail= rebases state_file wake! adapter_for adapter_of resume stay?
                  job signal].freeze

      # @param runner [OpenLanes::Engine::Runner]
      # @param state [OpenLanes::Engine::StateFile, nil] nil under a dry run
      # @param rounds [Integer, nil] `--rounds`, a cap that only tightens
      # @param sleeper [Proc, nil] how a tick waits; the suite passes a no-op.
      #   Kept beside +clock+ until 045; nil waits on +clock+
      # @param clock [#now, #sleep] the time source, {OpenLanes::Clock::System}
      #   unless a spec moves time itself
      # @param on_board [Proc, nil] receives a {Board} each tick
      # @param stay [Boolean] keep running past every fixed point, idle, until
      #   a person stops the run
      # @param rescan [Integer] idle ticks, {TICK} seconds each, between
      #   rescans of the tree while staying
      # @param watch [OpenLanes::Engine::PrWatch, nil] the watch over open pull
      #   requests (M4), in every merge mode (#171); nil in a dry run or when
      #   the run does not stay
      # @param converter [#call, nil] rewrites prose questions into choices
      #   (D9); nil, as without OPENROUTER_API_KEY, leaves them as written
      # @param journal [OpenLanes::Engine::EventJournal, nil] the progress
      #   journal (S9); nil keeps none
      # @param budget [OpenLanes::Engine::Budget, nil] the dollar cap per plan
      #   (plan 062.00); nil reads it from the runner's event log
      def initialize(runner:, state: nil, rounds: nil, sleeper: nil, clock: Container["clock"], on_board: nil,
        stay: false, rescan: RESCAN, watch: nil, converter: Live.choice_converter, extensions: nil, journal: nil,
        budget: nil)
        @desk = Desk.new(runner:, state:, rounds:, clock:, stay:, journal:, extensions:, budget:)
        # The desk's own collections under the names the suite reads them by.
        @holds = @desk.holds
        @finished_plans = @desk.finished_plans
        @discarding = @desk.discarding
        @tick_lock = Monitor.new
        @sleeper = sleeper || ->(seconds) { clock.sleep(seconds) }
        @on_board = on_board
        @before_tick = []
        @conversions = Conversions.new(converter:, runner:, find: @desk.method(:fresh_by))
        @stranded = Recovery::Stranded.new(runner:, state:, records: @desk.records, clock:)
        build_tick(rescan)
        build_steps(watch)
      end

      # What the loop and its steps share lives on the {Desk}; the loop
      # reads it under the names the steps do.
      def_delegators :@desk, *Desk.public_instance_methods(false)
      private(*(Desk.public_instance_methods(false) - PUBLIC))

      # @!method board
      #   @return [OpenLanes::Engine::Board] see {Rows#board}
      def_delegators :@rows, :board

      # @!method discard(ordinal)
      #   @return [OpenLanes::Engine::Dispatcher::Discard] see {Lanes#discard}
      # @!method fence(ordinals)
      #   @return [void] see {Lanes#fence}
      # @!method stop_plan(ordinal)
      #   @return [Array<String>] see {Lanes#stop_plan}
      # @!method restart_plan(ordinal)
      #   @return [void] see {Lanes#restart_plan}
      def_delegators :@lanes, :discard, :fence, :stop_plan, :restart_plan

      # Asked of the loop by name in the suite, and answered by the step
      # each one moved to.
      def_delegators :@assign, :idle_reason, :blockers_first
      def_delegators :@rename, :apply_hold
      def_delegators :@poll, :record_journal
      private :idle_reason, :blockers_first, :apply_hold, :record_journal

      # @return [Array<OpenLanes::Engine::Runner::Attempt>]
      def run
        feed.append(:run_started, jobs: runner.jobs)
        resume_stranded(reattach)
        loop do
          tick
          break if done?

          @sleeper.call(TICK)
        end
        feed.append(:run_ended, reason: Execution::Control.quit? ? "quit" : "fixed point")
        attempts
      end

      # One cycle. Public so the suite can drive it by hand.
      #
      # One tick at a time: two that overlapped each read the plan as free
      # and handed it to an agent apiece (the stress spec saw one plan
      # started eight times by eight ticks). A `Monitor`, so a hook that
      # ticks from inside a tick does not deadlock on itself.
      #
      # @return [void]
      def tick
        @tick_lock.synchronize do
          @before_tick.each { |hook| hook.call(self) }
          @settle.reap
          @lanes.finish_discards
          unblocking.call
          convert_questions
          @poll.poll
          @poll.ask_for_time
          @poll.drain_mail
          @watching&.call
          @rulings.arbitrate
          @rulings.settle_verifications
          @merges.call
          @sweeps.call
          # On threads: a kill waits out TERM before KILL, and the board must not.
          running.each { |job| Thread.new { job.handle.kill!(grace: 0, reason: :quit) } } if Execution::Control.overdue?
          @assign.dispatch unless Execution::Control.quit? || @assign.resting?
          persist
          @on_board&.call(board)
        end
      end

      # A run ends at a fixed point: nothing running and nothing left to
      # start. A staying run (the engine with its control room) never ends on
      # its own, not even once every plan is {FINISHED}: the page can create
      # the next plan at any moment, and a run that had quit would leave it
      # nowhere to go. Only a quit ends it (Stop Local Workers, Ctrl-C, SIGTERM),
      # once the agents have gone.
      #
      # @return [Boolean]
      def done?
        return false unless quiet?
        # A quit does not wait for a look: it only reads, and the coverage
        # run under it is a child process killed at exit.
        return true if Execution::Control.quit?
        return false if stay?
        # Nor does an ending run return in the middle of one: what it finds
        # is acted on, on the next tick, before the run reports.
        return false if runner.verification&.busy? || runner.arbitration&.busy?

        @assign.next_dispatchable.nil?
      end

      # Kill from a view: STOP, {KILL_GRACE} seconds, SIGKILL, on a thread
      # so the tick is not held for fifteen seconds.
      #
      # @param key [String] a row's key
      # @return [void]
      def kill(key)
        job = running.find { |j| j.key == key } or return
        Thread.new { job.handle.kill!(grace: KILL_GRACE) }
      end

      # More time, from a view.
      #
      # @param key [String]
      # @param seconds [Integer]
      # @return [Boolean] whether a running agent's clock moved
      def extend(key, seconds)
        job = running.find { |j| j.key == key } or return false
        return false unless job.handle&.extend!(seconds)

        feed.append(:extension, plan: job.task.subject.feature.ordinal.to_s, agent: job.task.agent.name, seconds:)
        true
      end

      # A person's answer to an `X<n>` request (E1). A time choice reaches
      # the agent's clock while that agent still runs on the plan; otherwise
      # the answer is one more round.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param number [Integer]
      # @param letter [String]
      # @param by [String]
      # @return [Hash, nil] the request as settled, nil when it already was
      def answer_extension(subject, number, letter, by:)
        request = Plans::PlanState.for(subject.feature.path).extensions.find { it["number"] == number }
        live = request && job("#{subject.feature.ordinal}/#{request["agent"]}")&.handle
        extensions.answer!(subject.feature.path, number, letter, by:, live:).tap { wake! }
      end

      # Something to run at the top of every tick, on the loop thread, where
      # {#running} may be read and changed safely: the live run applies the
      # page's commands here.
      #
      # @yieldparam dispatcher [OpenLanes::Engine::Dispatcher]
      # @return [void]
      def before_tick(&hook) = @before_tick << hook

      # Stop the agent with a resume note and give it its round back, so it
      # is started again, on whatever model is now preferred, as soon as it
      # has stopped. The agent is told INTERRUPT, which is the word that
      # makes it leave the note.
      #
      # @param key [String]
      # @return [Boolean] whether there was a running agent to restart
      def requeue(key)
        signal(key, Execution::Control::INTERRUPT) or return false
        requeues << key unless requeues.include?(key)
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

      # The model one agent gets on one plan from its next invocation (W24).
      #
      # @param ordinal [#to_s]
      # @param agent [String]
      # @param model [String, nil] nil forgets the choice
      # @return [Boolean] whether the executor can honour it
      def prefer_model(ordinal, agent, model)
        executor = runner.executor
        return false unless executor.respond_to?(:prefer_model)

        executor.prefer_model(ordinal, agent, model)
        models.delete([ordinal.to_s, agent.to_s])
        true
      end

      # The copilot's `/concurrency N`. Never signals a running agent.
      #
      # @param count [Integer]
      # @return [void]
      # @raise [OpenLanes::Error] as {Runner#jobs=} does
      def concurrency=(count)
        runner.jobs = count
      end

      private

      # The tick's own steps (plan 060, item 5), each handed the desk and
      # the steps it calls on. The order here is only who needs whom; the
      # order they run in is {#tick}'s.
      #
      # @param rescan [Integer]
      # @return [void]
      def build_tick(rescan)
        @poll = Poll.new(@desk)
        @rename = Rename.new(@desk)
        @rows = Rows.new(@desk, waiting_on: -> { @watching&.waiting_on || {} })
        @settle = Settle.new(@desk, rename: @rename, poll: @poll, row: @rows.method(:row_for))
        @start = Start.new(@desk, rename: @rename, settle: @settle)
        @assign = Assign.new(@desk, start: @start, rescan:)
        @lanes = Lanes.new(@desk)
        @rulings = Rulings.new(@desk)
      end

      # The tick's polls and drains, each a class of its own (045), handed
      # what they need of this loop as callables.
      #
      # @param watch [PrWatch, nil]
      # @return [void]
      def build_steps(watch)
        context = Steps::Context.new(runner:,
          busy:   method(:untouchable),
          wake:   method(:wake!),
          reopen: ->(ordinal) { finished_plans.delete(ordinal) })
        @merges = Steps::Merges.new(context)
        @sweeps = Steps::Sweeps.new(context, resolve: @start.method(:resolve_conflict))
        @watching = watch && Steps::Watch.new(context, watch:, finishes:, state: state_file)
        @unblocking = @desk.unblocking = Unblocking.drainer(context, history: method(:clear_blocked))
      end

      # A drained plan's agents get their rounds back: a block is a question,
      # not the agent running out of turns.
      #
      # @param ordinal [String]
      # @return [void]
      def clear_blocked(ordinal)
        mutex.synchronize do
          history.each { |(plan, _), entries| entries.reject! { it[:status] == "Blocked" } if plan == ordinal }
        end
      end

      # Prose questions go to the model off the tick thread; what it wrote
      # comes back on a later tick (D9). A quitting or dry run applies what
      # already came back and sends nothing new.
      #
      # @return [void]
      def convert_questions
        @conversions.call(busy: untouchable, start: !(runner.dry_run? || Execution::Control.quit?))
      end

      # @param reattached [Array<Array(String, String, Integer)>] stages {#reattach} took back
      # @return [void] see {Recovery::Stranded}
      def resume_stranded(reattached = []) = @stranded.call(skip: reattached)

      # The agents a dead engine left, taken back before anything else is
      # started (B1 in plan 041). A verifier's preview app died with that
      # engine, so a verifier is stopped instead, and resumed as stranded
      # (B9). From here on this engine's own agents outlive its crash.
      #
      # @return [Array<Array(String, String, Integer)>] the stages taken back
      def reattach
        return [] unless state_file

        Execution::AgentProcess.reattachable!
        Recovery::Reattach.new(runner:, state: state_file).call.filter_map do |found|
          next @start.adopt(found) unless verifier?(found.agent)

          Execution::AgentProcess.attach(found.restart["process"]).tap(&:terminate).wait
          nil
        end
      end

      # @return [void]
      def persist
        return unless state_file

        state_file.heartbeat!
        state_file.save
      end
    end
  end
end
