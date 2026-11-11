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
    class Dispatcher
      extend Forwardable

      # One running invocation. `from` is the state the plan showed when the
      # agent was picked; `state` is the one it ran under, after any
      # `starts_as` rename. History is keyed by `state`: backend-coder picked at ⭐
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
        :rebase,
        :recorded_session,
        :journal,
        :journaled,
        :journal_round,
        :sweep) do
        # @return [Boolean]
        def finished? = !thread.alive?
      end

      # A plan a person is throwing back (W9): its agents stopping, then its
      # worktree reset and its folder moved back to the state their work
      # started from. {Live::Commands} holds on to it and replies once
      # {#finished?}.
      #
      # @!attribute [r] ordinal
      #   @return [String]
      # @!attribute [r] status
      #   @return [String, nil] "done" or "refused", once it is over
      # @!attribute [r] reason
      #   @return [String, nil]
      # @!attribute [r] from
      #   @return [Symbol, nil] the state the stopped agents started from,
      #     nil when none was running, which means one step back
      Discard = Struct.new(:ordinal, :status, :reason, :from) do
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
      Published = Data.define(:attempt, :subject, :refused, :untestable) do
        def initialize(untestable: false, **rest) = super
      end

      # Who the harness signs its own mail as.
      HARNESS = Recovery::HARNESS

      # What a builder is told when its finished work has no way to be tested.
      HOW_TO_TEST_MAIL = <<~MAIL.freeze
        The build is done, but the pull request was not opened: plan.md has no
        `#{Lifecycle::Completion::HOW_TO_TEST}` section, and a pull request nobody can test is not
        ready for review. Add one to plan.md: the commands to run and what a person
        should see, as a list, covering every part of the build and not only yours.
        Change nothing else, then sign Completed again.
      MAIL

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
      PUBLIC = %i[running runner attempts mail mail= rebases state_file wake! adapter_for adapter_of resume stay?].freeze

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
      def initialize(runner:, state: nil, rounds: nil, sleeper: nil, clock: Clock::System, on_board: nil,
        stay: false, rescan: RESCAN, watch: nil, converter: Live.choice_converter, extensions: nil, journal: nil)
        @desk = Desk.new(runner:, state:, rounds:, clock:, stay:, journal:, extensions:)
        # The desk's own collections under the names the suite reads them by.
        @holds = @desk.holds
        @finished_plans = @desk.finished_plans
        @discarding = @desk.discarding
        @tick_lock = Monitor.new
        @sleeper = sleeper || ->(seconds) { clock.sleep(seconds) }
        @on_board = on_board
        @started_at = UI.monotonic
        @before_tick = []
        @conversions = Conversions.new(converter:, runner:, find: @desk.method(:fresh_by))
        @stranded = Recovery::Stranded.new(runner:, state:, records: @desk.records, clock:)
        @poll = Poll.new(@desk)
        @rename = Rename.new(@desk)
        @settle = Settle.new(@desk, rename: @rename, poll: @poll, row: method(:row_for))
        @start = Start.new(@desk, rename: @rename, settle: @settle)
        @assign = Assign.new(@desk, start: @start, rescan:)
        build_steps(watch)
      end

      # What the loop and its steps share lives on the {Desk}; the loop
      # reads it under the names the steps do.
      def_delegators :@desk, *Desk.public_instance_methods(false)
      private(*(Desk.public_instance_methods(false) - PUBLIC))

      def_delegators :@poll, :poll, :ask_for_time, :drain_mail, :record_journal
      private :poll, :ask_for_time, :drain_mail, :record_journal

      def_delegators :@rename, :rename_on_start, :complete, :park, :assessed, :apply_hold
      private :rename_on_start, :complete, :park, :assessed, :apply_hold

      def_delegators :@settle, :reap, :end_replacements
      private :reap, :end_replacements

      def_delegators :@start, :start, :adopt, :resolve_conflict
      private :start, :adopt, :resolve_conflict

      def_delegators :@assign, :dispatch, :resting?, :next_dispatchable, :idle_reason, :blockers_first
      private :dispatch, :resting?, :next_dispatchable, :idle_reason, :blockers_first

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
          reap
          finish_discards
          unblocking.call
          convert_questions
          poll
          ask_for_time
          drain_mail
          @watching&.call
          arbitrate
          settle_verifications
          @merges.call
          @sweeps.call
          # On threads: a kill waits out TERM before KILL, and the board must not.
          running.each { |job| Thread.new { job.handle.kill!(grace: 0, reason: :quit) } } if Execution::Control.overdue?
          dispatch unless Execution::Control.quit? || resting?
          persist
          @on_board&.call(board)
        end
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
        # A quit does not wait for a look: it only reads, and the coverage
        # run under it is a child process killed at exit.
        return true if Execution::Control.quit?
        return false if stay?
        # Nor does an ending run return in the middle of one: what it finds
        # is acted on, on the next tick, before the run reports.
        return false if runner.verification&.busy? || runner.arbitration&.busy?

        next_dispatchable.nil?
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
      # @return [void]
      def extend(key, seconds)
        job = running.find { |j| j.key == key } or return
        job.handle&.extend!(seconds)
        feed.append(:extension, plan: job.task.subject.feature.ordinal.to_s, agent: job.task.agent.name, seconds:)
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

      # @param key [String] a row's key, `"<ordinal>/<agent>"`
      # @return [OpenLanes::Engine::Dispatcher::Job, nil]
      def job(key) = running.find { |j| j.key == key }

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

      # Throw a plan's work away (W9): every agent on it is stopped, each with
      # {KILL_GRACE} seconds to finish the line it is writing, and once the
      # last is gone the plan's worktree is reset and its folder sent back
      # to the state that work started from (see {#started_from}).
      # Plan-wide, because a pair shares one worktree and a reset takes both
      # halves. What can be refused is refused here, before any agent is
      # stopped.
      #
      # @param ordinal [#to_s]
      # @return [OpenLanes::Engine::Dispatcher::Discard] finished on a later tick
      # @raise [OpenLanes::Error] with the reason it cannot be done
      def discard(ordinal)
        ordinal = ordinal.to_s
        return discarding[ordinal] if discarding.key?(ordinal)

        if !runner.isolated? || runner.dry_run?
          raise OpenLanes::Error,
            "discard resets the plan's own worktree, and this run has none: under --isolation shared " \
            "or a dry run every agent works in the main checkout, which a reset would wipe. " \
            "Use stop on each agent instead."
        end
        subject = fresh_by(Plans::Ordinal.parse(ordinal)) or raise OpenLanes::Error, "there is no plan #{ordinal}"
        jobs = running.select { plan_of(it) == ordinal }
        from = started_from(jobs)
        refusal = subject.machine.retreat_refusal(from) and raise OpenLanes::Error, "#{ordinal} cannot go back: #{refusal}"

        jobs.each do |job|
          Thread.new { job.handle.kill!(grace: KILL_GRACE, reason: :discard) }
        end
        discarding[ordinal] = Discard.new(ordinal:, from:)
      end

      # Plans whose claim another machine now holds (W26): their agents are
      # stopped, each with {KILL_GRACE} seconds, the plans leave this run,
      # and nothing this node does afterwards signs or renames for them.
      #
      # @param ordinals [Array<String>]
      # @return [void]
      def fence(ordinals)
        ordinals.map(&:to_s).each do |ordinal|
          fenced << ordinal unless fenced.include?(ordinal)
          runner.drop_plan(ordinal)
          running.select { plan_of(it) == ordinal }.each do |job|
            UI.log("claim lost; stopping", level: :warn, **job.task.log_fields)
            Thread.new { job.handle.kill!(grace: KILL_GRACE, reason: :fenced) }
          end
        end
      end

      # The copilot's `/stop NNN`: every agent on the plan is told STOP, and
      # the plan leaves this run so the next tick does not start it again.
      # Its claim is let go, so the plan is free for any machine.
      #
      # @param ordinal [#to_s]
      # @return [Array<String>] the keys told STOP
      # @raise [OpenLanes::Error] when the plan is neither running nor in scope
      def stop_plan(ordinal)
        ordinal = ordinal.to_s
        keys = running.select { plan_of(it) == ordinal }.map(&:key)
        if keys.empty? && !in_run?(ordinal)
          raise OpenLanes::Error, "#{ordinal} is not on this run's board: no agent is working it and it is not in scope"
        end

        told = keys.select { signal(it, Execution::Control::STOP) }
        runner.drop_plan(ordinal)
        runner.release(ordinal)
        told
      end

      # The copilot's `/restart NNN`, for a lane that lost its agent (a Redis
      # glitch, a killed process): the plan is put back in scope, the rounds
      # it used up here are forgotten, and the next tick dispatches it. A
      # plan with an agent on it already is left alone.
      #
      # @param ordinal [#to_s]
      # @return [void]
      # @raise [OpenLanes::Error] when an agent is working it, or it is not on
      #   this node's board
      def restart_plan(ordinal)
        ordinal = ordinal.to_s
        working = running.select { plan_of(it) == ordinal }.map { it.task.agent.name }
        raise OpenLanes::Error, "#{ordinal} already has an agent: #{working.join(", ")}" unless working.empty?

        subject = fresh_by(Plans::Ordinal.parse(ordinal))
        unless subject && (in_run?(ordinal) || runner.dropped?(ordinal)) && !runner.foreign?(subject)
          raise OpenLanes::Error, "#{ordinal} is not on this node's board"
        end

        runner.add_plan(subject.feature.ordinal)
        mutex.synchronize { history.delete_if { |(plan, _), _| plan == ordinal } }
        finished_plans.delete(ordinal)
        wake!
      end

      # The copilot's `/concurrency N`. Never signals a running agent.
      #
      # @param count [Integer]
      # @return [void]
      # @raise [OpenLanes::Error] as {Runner#jobs=} does
      def concurrency=(count)
        runner.jobs = count
      end

      # @return [OpenLanes::Engine::Board]
      def board
        up = attempts.sum(&:up) + running.sum { |j| j.up.to_i }
        down = attempts.sum(&:down) + running.sum { |j| j.down.to_i }
        Board.new(started_at: @started_at,
          status: run_status,
          plans: (running.map { |j| j.task.subject.feature.ordinal.to_s } + recent.map { |r| r[:row].ordinal } +
                  waiting + finishes.ordinals).uniq,
          up:,
          down:,
          rows: rows,
          root: runner.root,
          running: running.size,
          live_up: running.sum { |j| j.up.to_i },
          live_down: running.sum { |j| j.down.to_i },
          waiting_on: (@watching&.waiting_on || {}).dup,
          jobs: runner.jobs)
      end

      private

      # The tick's polls and drains, each a class of its own (045), handed
      # what they need of this loop as callables.
      #
      # @param watch [PrWatch, nil]
      # @return [void]
      def build_steps(watch)
        context = Steps::Context.new(runner: runner,
          busy:   method(:untouchable),
          wake:   method(:wake!),
          reopen: ->(ordinal) { finished_plans.delete(ordinal) })
        @merges = Steps::Merges.new(context)
        @sweeps = Steps::Sweeps.new(context, resolve: method(:resolve_conflict))
        @watching = watch && Steps::Watch.new(context, watch:, finishes: finishes, state: state_file)
        @unblocking = @desk.unblocking = Unblocking.drainer(context, history: method(:clear_blocked))
      end

      # @return [Symbol]
      def run_status
        return :quitting if Execution::Control.quit?
        return :wrapping_up if running.any? { |j| %i[wrap_up stopped].include?(j.handle.phase) }
        return :idle if idle && quiet?

        :running
      end

      # @return [Array<OpenLanes::Engine::Board::Row>]
      def rows
        now = UI.monotonic
        recent.reject! { |r| now - r[:at] > LINGER }
        running.map { |job| row_for(job) } + recent.map { |r| r[:row] }
      end

      # ---- finished plans ---------------------------------------------------

      # ---- discarding -------------------------------------------------------

      # Discards whose agents have all gone: the worktree is reset and the
      # folder moved back. A finished one stays one tick, for
      # {Live::Commands} to reply from, and is dropped on the next.
      #
      # @return [void]
      def finish_discards
        discarding.delete_if { |_, discard| discard.finished? }
        discarding.each_value do |discard|
          next if running.any? { plan_of(it) == discard.ordinal }

          discard.status, discard.reason = throw_back(discard)
        end
      end

      # The state the discarded work started from: each job's {Job#from},
      # the state the plan showed when it was picked. Only an agent with
      # `starts_as` moved the folder on, so stepping back from the folder's
      # own state sent every other agent's plan one phase too far (issue
      # #173). A pair can be picked on either side of backend-coder's
      # `starts_as` rename, so the earliest of its starts wins: the one with
      # the longest road ahead of it.
      #
      # @param jobs [Array<OpenLanes::Engine::Dispatcher::Job>]
      # @return [Symbol, nil] nil when no agent was running
      def started_from(jobs) = jobs.map(&:from).compact.uniq.max_by { Plans::StateMachine.onward(it).size }

      # @param discard [OpenLanes::Engine::Dispatcher::Discard]
      # @return [Array(String, String)] status and reason
      def throw_back(discard)
        ordinal = discard.ordinal
        subject = fresh_by(Plans::Ordinal.parse(ordinal)) or return ["refused", "#{ordinal}'s folder vanished"]
        reset = runner.worktree.reset(subject.feature)
        from = subject.status
        to = subject.machine.retreat!(discard.from)
        finished_plans.delete(ordinal)
        UI.log("discarded: #{from} -> #{to}", plan: ordinal)
        moved = to.key == from.key ? "stays at #{to}, where its work started" : "went back from #{from} to #{to}"
        ["done", "#{ordinal} #{reset ? "reset" : "had no worktree to reset"}, and #{moved}"]
      rescue OpenLanes::Error => e
        ["refused", "#{ordinal}'s agents were stopped, but: #{e.message}"]
      end

      # ---- unblocking ------------------------------------------------------

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

      # @param job [OpenLanes::Engine::Dispatcher::Job]
      # @return [OpenLanes::Engine::Board::Row]
      def row_for(job)
        task = job.task
        job.frame = job.frame.to_i + 1
        Board::Row.new(key: job.key,
          at: clock.now,
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

        subject = Plans::Tree.new(dir: runner.tree.dir).find(task.subject.feature.ordinal) or return nil
        pull = subject.pull_requests.find(&:open?) or return nil
        { number: pull.number, url: pull.url, rejected: subject.status.key == :rejected }
      end

      # ---- starting ---------------------------------------------------------

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
        Recovery::Reattach.new(runner: runner, state: state_file).call.filter_map do |found|
          next adopt(found) unless verifier?(found.agent)

          Execution::AgentProcess.attach(found.restart["process"]).tap(&:terminate).wait
          nil
        end
      end

      # ---- staying ----------------------------------------------------------

      # ---- more time, more rounds (E1) ---------------------------------------

      # ---- polling ----------------------------------------------------------

      # ---- settling ---------------------------------------------------------

      # ---- merging (P1 to P5) ------------------------------------------------

      # ---- pull requests nobody is working on (U1 to U4) --------------------

      # ---- verification (plan 014) -----------------------------------------

      # The arbitrator's step (plan 015): every plan nothing is running on is
      # asked for a trigger, and a ruling that came back is applied before
      # anything is assigned, so a capped plan never reaches its builders.
      # The agent itself runs off this thread; see {Arbitration#tick}.
      #
      # @return [void]
      def arbitrate
        arbitration = runner.arbitration or return
        return if runner.dry_run?

        # The plans being asked about are untouchable to everything but the
        # ruling, which is about to be applied.
        busy = untouchable - arbitration.asking
        arbitration.tick(runner.in_scope.reject { busy.include?(it.feature.ordinal.to_s) }).each do |outcome|
          note = outcome.error || outcome.effects.ruling.values_at("kind", "outcome").join(": ")
          UI.log("⚖️ #{outcome.trigger}: #{note}", level: outcome.error ? :warn : :info, plan: outcome.plan)
          # A ruling moved the plan or freed it for its builders; a refused
          # one waits out its back-off, so nothing is worth a rescan for it.
          wake! unless outcome.error
        end
      end

      # What the last look at CI found for the verified plans, logged, and
      # the plans it moved woken for. A rejection hands the plan back to the
      # builders; `ready-to-merge` leaves it at 🧪 for a person, or plan
      # 033's merge, to finish.
      #
      # @return [void]
      def settle_verifications
        driver = runner.verification or return
        return if runner.dry_run?

        # The plans being looked at are untouchable to everything but the
        # look itself, which is about to be acted on.
        busy = untouchable - driver.looking
        subjects = runner.in_scope.reject { busy.include?(it.feature.ordinal.to_s) }
        driver.poll(subjects).each do |settled|
          result = settled.result
          waiting = Verification::Outcome::WAITING.include?(result.kind)
          verifying[settled.plan] = result.note if waiting
          next if waiting && said_verifying[settled.plan] == result.note

          said_verifying[settled.plan] = result.note
          verifying.delete(settled.plan) unless waiting
          finished_plans.delete(settled.plan) if result.to
          # Stalled is a warning: CI pending past `ci_pending_hours` waits on
          # a person, and an info line among the waits would never be seen.
          UI.log(result.note, level: %i[rejected stalled].include?(result.kind) ? :warn : :info, plan: settled.plan)
          wake!
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
