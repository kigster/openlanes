# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # What the tick's steps share: the jobs running now, what each agent
      # has already done on each plan, the plans nothing may touch, and the
      # collaborators every step reads or writes through.
      #
      # One desk per run, built by the {Dispatcher} and handed to each
      # {Step}. The collections here are mutated in place and never
      # replaced, so every step sees the same list of running jobs the loop
      # does. Only the loop's thread writes them, except the history, which
      # the page's commands also reach and which is why it has a mutex.
      class Desk
        # @param runner [OpenLanes::Engine::Runner]
        # @param state [OpenLanes::Engine::StateFile, nil] nil under a dry run
        # @param rounds [Integer, nil] `--rounds`, a cap that only tightens
        # @param clock [#now, #sleep]
        # @param stay [Boolean] whether the run idles past its fixed points
        # @param journal [OpenLanes::Engine::EventJournal, nil]
        # @param extensions [OpenLanes::Engine::Extensions, nil]
        # @param budget [OpenLanes::Engine::Budget, nil] nil reads the cap and
        #   the spend from the runner's own event log
        def initialize(runner:, state:, rounds:, clock:, stay:, journal:, extensions:, budget: nil)
          @runner = runner
          @budget = budget || Engine.budget_for(runner)
          @said_budget = {}
          @state_file = state
          @rounds_cap = rounds
          @clock = clock
          @stay = stay
          @feed = EventJournal::Feed.new(journal)
          @extensions = extensions || Extensions.new(stay:)
          @idle = false
          @wake = false
          @running = []
          @recent = []
          @attempts = []
          @history = Hash.new { |h, k| h[k] = [] }
          @finished_plans = []
          @asked_how_to_test = Set.new
          @preferred_agents = {}
          @invocations = {}
          @mutex = Mutex.new
          @requeues = []
          @discarding = {}
          # Pair holds not yet applied, ordinal => state (issue #172).
          @holds = {}
          @fenced = []
          @models = {}
          # Agents outside openlanes (W31). A dry run claims nothing, so it
          # asks nothing either.
          @agent_locks = runner.dry_run? ? nil : Engine.agent_locks(runner.tree.dir, own: runner.agents.all.map(&:name))
          @said_outside = {}
          @refusals = Set.new
          @locks = PlanLocks.new(agent_locks: @agent_locks)
          # A dry run writes no state.json, so it starts no lock's clock.
          @lock_clock = runner.dry_run? ? nil : Plans::LockClock.new
          @verifying = {}
          @said_verifying = {}
          @finishes = Finishes.new(runner:, clock:)
          @records = Recovery::Records.new(dry_run: runner.dry_run?)
        end

        # @return [OpenLanes::Engine::Runner]
        attr_reader :runner

        # @return [OpenLanes::Engine::StateFile, nil] nil under a dry run
        attr_reader :state_file

        # @return [Integer, nil] `--rounds`
        attr_reader :rounds_cap

        # @return [#now, #sleep]
        attr_reader :clock

        # @return [OpenLanes::Engine::EventJournal::Feed]
        attr_reader :feed

        # @return [OpenLanes::Engine::Extensions]
        attr_reader :extensions

        # @return [Array<OpenLanes::Engine::Dispatcher::Job>]
        attr_reader :running

        # @return [Array<Hash>] settled rows still on the screen, `{ at:, row: }`
        attr_reader :recent

        # @return [Array<OpenLanes::Engine::Runner::Attempt>]
        attr_reader :attempts

        # @return [Hash{Array(String, String) => Array<Hash>}] each agent's
        #   rounds on each plan, by `[ordinal, agent]`; guarded by {#mutex}
        attr_reader :history

        # @return [Array<String>] plans with nothing left for this run to do
        attr_reader :finished_plans

        # @return [Set<String>] plans whose builder was mailed about `How to test`
        attr_reader :asked_how_to_test

        # @return [Hash{String => String}] the agent a `next:` named, by ordinal
        attr_reader :preferred_agents

        # @return [Hash{String => Time}] when each running job was invoked, by key
        attr_reader :invocations

        # @return [Mutex] guards {#history} and {#asked_how_to_test}
        attr_reader :mutex

        # @return [Array<String>] keys of jobs a person asked to run again
        attr_reader :requeues

        # @return [Hash{String => OpenLanes::Engine::Dispatcher::Discard}]
        attr_reader :discarding

        # @return [Hash{String => Symbol}] pair holds not yet applied
        attr_reader :holds

        # @return [Array<String>] plans whose claim another machine took
        attr_reader :fenced

        # @return [Hash{Array(String, String) => String}] model labels, by
        #   `[ordinal, agent]`, so spec.md is read once and not once a frame
        attr_reader :models

        # @return [OpenLanes::Engine::AgentLocks, nil] nil under a dry run
        attr_reader :agent_locks

        # @return [Hash{String => String, nil}] the outside holder last said, by ordinal
        attr_reader :said_outside

        # @return [Set<String>] plans this pass could not claim
        attr_reader :refusals

        # @return [OpenLanes::Engine::PlanLocks]
        attr_reader :locks

        # @return [OpenLanes::Plans::LockClock, nil] nil under a dry run
        attr_reader :lock_clock

        # @return [Hash{String => String}] what each verified plan waits on
        attr_reader :verifying

        # @return [Hash{String => String}] the wait last logged, by ordinal
        attr_reader :said_verifying

        # @return [OpenLanes::Engine::Finishes]
        attr_reader :finishes

        # @return [OpenLanes::Engine::Recovery::Records]
        attr_reader :records

        # Mail over Redis; see {Dispatcher#mail}.
        #
        # @return [OpenLanes::Live::Mail, nil]
        attr_accessor :mail

        # The drain of answered blocks, set once the dispatcher has built it:
        # it needs {#untouchable}, and {#untouchable} needs it.
        #
        # @return [OpenLanes::Engine::Unblocking::Drainer]
        attr_accessor :unblocking

        # @return [Boolean] whether the last dispatch found nothing to start
        attr_accessor :idle

        # @return [Boolean] whether a rescan was asked for on the next tick
        attr_accessor :wake

        # @return [Boolean] whether this run idles past its fixed points
        def stay? = @stay

        # Stopped rebases and how often each plan's has failed; see {Rebase}.
        #
        # @return [OpenLanes::Engine::Rebase]
        def rebases = @rebases ||= Rebase.new(agents: runner.agents, executor: runner.executor)

        # Rescan on the next tick rather than at the end of the interval: a
        # command was applied, and what it changed should be acted on now.
        #
        # @return [void]
        def wake! = @wake = true

        # The CLI a running agent was started on, which is what decides whether
        # its session can be resumed.
        #
        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [OpenLanes::Adapters::Base]
        def adapter_for(job) = adapter_of(job.task.agent, job.task.subject)

        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject]
        # @return [OpenLanes::Adapters::Base]
        def adapter_of(agent, subject)
          executor = runner.executor
          return Agents::Profile.resolve(agent).adapter unless executor.respond_to?(:profile_for)

          executor.profile_for(agent, subject).adapter
        end

        # Hand back the round an interrupted agent lost, so a person's "resume"
        # starts it again even when it had no rounds left.
        #
        # @param ordinal [#to_s]
        # @param agent [String]
        # @return [Boolean] whether there was an interrupted round to hand back
        def resume(ordinal, agent)
          mutex.synchronize do
            entries = history[[ordinal.to_s, agent.to_s]]
            last = entries.rindex { |h| h[:status] == "Interrupted" } or next false
            entries.delete_at(last)
            true
          end
        end

        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [String] the plan's ordinal
        def plan_of(job) = job.task.subject.feature.ordinal.to_s

        # @param ordinal [String]
        # @return [Boolean] whether the plan is in this run's scope now
        def in_run?(ordinal)
          subject = fresh_by(Plans::Ordinal.parse(ordinal))
          !subject.nil? && runner.in_scope?(subject)
        end

        # Plans no agent may be started on and no rename may touch: one being
        # discarded or drained, one another machine holds (W26), and one whose
        # `locked-by.pid` another run wrote.
        #
        # @return [Array<String>]
        def untouchable
          busy = running.map { plan_of(it) } + discarding.keys + unblocking.map(&:ordinal) + verifying_now + arbitrating_now
          busy + runner.tree.subjects.select { runner.foreign?(it) || locked_elsewhere?(it) || held_outside?(it) }
                       .map { it.feature.ordinal.to_s }
        end

        # Plans whose CI and coverage are being looked at off the loop's
        # thread. Untouchable until the look is acted on: a builder started
        # in the checkout the suite is running in, or a person's rejection
        # renaming the folder under it, would leave the look acting on a plan
        # that is no longer the one it read.
        #
        # @return [Array<String>]
        def verifying_now = runner.verification&.looking || []

        # Plans the arbitrator is being asked about off the loop's thread,
        # untouchable for the same reason until its ruling is applied.
        #
        # @return [Array<String>]
        def arbitrating_now = runner.arbitration&.asking || []

        # The Redis claim covers machines that share one; the lock file covers
        # a second run on this machine, or one that never reached Redis.
        # Without this check such a run renamed the folder at start, wrote its
        # own lock over the holder's, and deleted it when its agent finished.
        # This run's own lock is not a reason to stay out: a pair shares it.
        #
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Boolean]
        def locked_elsewhere?(subject) = Plans::Lock.read(subject.feature.path)&.held_elsewhere? || false

        # The dollar cap (plan 062.00): a plan past `budget.plan_usd` gets no
        # new agent, and is held as queued plans are, without a state fired or
        # a folder renamed. A query only: {#announce_budget} says it.
        #
        # @param subject [OpenLanes::Plans::Subject]
        # @return [String, nil] `over budget: $X of $Y`, or nil when it may run
        def budget_refusal(subject) = @budget.refusal(subject.feature.ordinal.to_s)

        # Says a budget hold once per reason, not on every tick.
        #
        # @param subject [OpenLanes::Plans::Subject]
        # @param reason [String, nil] what {#budget_refusal} answered
        # @return [void]
        def announce_budget(subject, reason)
          ordinal = subject.feature.ordinal.to_s
          UI.log("#{reason}; no new round starts", plan: ordinal, level: :warn) if reason && @said_budget[ordinal] != reason
          @said_budget[ordinal] = reason
        end

        # @return [Hash{String => String}] in-scope plans the cap holds, with why
        def budget_holds
          runner.in_scope.to_h { [it.feature.ordinal.to_s, budget_refusal(it)] }.compact
        end

        # An agent outside openlanes holds the plan's folder or its worktree in
        # alock (W31). Said once per holder, not on every tick it stays held.
        #
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Boolean]
        def held_outside?(subject)
          held = agent_locks&.held_elsewhere(subject.feature.path, checkout: runner.checkout_path(subject))
          ordinal = subject.feature.ordinal.to_s
          if held && said_outside[ordinal] != held
            UI.log("held outside openlanes by #{held}; stepping around it", plan: ordinal)
          end
          said_outside[ordinal] = held
          !held.nil?
        end

        # Nothing running, draining or being thrown back.
        #
        # @return [Boolean]
        def quiet? = running.empty? && unblocking.empty? && discarding.empty?

        # Blocked plans in scope that this machine may answer for: on the board
        # whether or not an agent touched them this run, so their questions
        # reach the page from the moment the run starts.
        #
        # @return [Array<String>] ordinals
        def waiting
          runner.blocked.reject { runner.foreign?(it) }.map { it.feature.ordinal.to_s }
        end

        # @param agent [OpenLanes::Agents::Agent]
        # @return [Integer]
        def rounds_for(agent)
          # A preview does nothing a second round could build on, and four
          # rounds of it listed every agent four times.
          return 1 if runner.dry_run?

          [agent.rounds, rounds_cap].compact.min
        end

        # Every round the agent may run on the plan's state: its own, plus the
        # ones a person or the harness granted (E1). What the board shows as
        # "Round 2 of 3": {#rounds_for} alone read "Round 4 of 1" on an agent
        # running its third extension, which told a person nothing about how
        # many more there were.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Integer]
        def rounds_allowed(agent, subject)
          return rounds_for(agent) if runner.dry_run?

          rounds_for(agent) + extensions.rounds(subject.feature.path, agent.name, subject.status.key)
        end

        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject, nil] whose spec.md may override it
        # @param root [String, nil] the plan's checkout, whose diff picks a `small_diff:` model
        # @return [String]
        def model_for(agent, subject = nil, root: nil)
          executor = runner.executor
          unless subject && executor.respond_to?(:profile_for)
            return (executor.respond_to?(:model) && executor.model) || agent.model || "default"
          end

          # Asked on every frame of the board, so spec.md is read once per plan
          # and agent rather than once per frame.
          models[[subject.feature.ordinal.to_s, agent.name, root]] ||=
            (root ? executor.profile_for(agent, subject, root:) : executor.profile_for(agent, subject)).label
        end

        # @param task [OpenLanes::Engine::Runner::Task]
        # @return [OpenLanes::Plans::Ledger::Reading]
        def read_ledger(task)
          subject = Plans::Tree.new(dir: runner.tree.dir).find(task.subject.feature.ordinal) or return Plans::Ledger::Reading.empty
          Plans::Ledger.read(subject.feature.path, task.agent.ledger)
        end

        # @param agent [OpenLanes::Agents::Agent]
        # @return [Boolean] whether this agent's run is wrapped in the plan's app
        def verifier?(agent) = agent.phase.to_s == Verification::PHASE && !runner.verification.nil? && !runner.dry_run?

        # @param agent [OpenLanes::Agents::Agent]
        # @return [Boolean] whether this agent's note carries merge verdicts
        def assessor?(agent) = agent.phase.to_s == Merging::PHASE && !runner.merging.nil?

        # @return [void] see {Recovery::Records#resume}
        def harness_resume(subject, agent, round, reason, last: last_line(subject, agent), phrase: nil)
          records.resume(Recovery::Round.new(subject:, agent:, round:), reason, last:, phrase:)
        end

        # @return [OpenLanes::Plans::Ledger::Entry, nil] see {Recovery::Records#last_line}
        def last_line(subject, agent) = records.last_line(Recovery::Round.new(subject:, agent:, round: nil))

        # @return [void] see {Recovery::Records#interrupted}
        def write_interrupted(subject, agent, round, reason)
          records.interrupted(Recovery::Round.new(subject:, agent:, round:), reason)
        end

        # @return [void] see {Recovery::Records#stage!}
        def stage!(subject, agent, round, **)
          records.stage!(Recovery::Round.new(subject:, agent:, round:), **)
        end

        # @return [Hash] adapter, model and effort, when the executor can say
        def profile_fields(agent, subject, root: nil)
          executor = runner.executor
          return {} unless executor.respond_to?(:profile_for)

          profile = root ? executor.profile_for(agent, subject, root:) : executor.profile_for(agent, subject)
          { adapter: profile.adapter.name, model: profile.model, effort: profile.effort }
        end

        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [Hash{Symbol => Object}] what every agent event of this job carries
        def event_fields(job)
          task = job.task
          { plan: task.subject.feature.ordinal.to_s, round: task.round, agent: task.agent.name,
            invocation_start: invocations[job.key], adapter: adapter_name(job), model: model_for(task.agent, task.subject, root: task.root) }
        end

        # @return [String, nil]
        def adapter_name(job)
          adapter_for(job).name.to_s
        rescue StandardError
          nil
        end

        # @return [OpenLanes::Plans::Subject, nil] the plan read fresh from the main tree
        def fresh(task) = fresh_by(task.subject.feature.ordinal)

        # @return [OpenLanes::Plans::Subject, nil]
        def fresh_by(ordinal) = Plans::Tree.new(dir: runner.tree.dir).find(ordinal)

        # One entry per round: the Started written at dispatch is overwritten by
        # the outcome rather than joined by it. Two entries a round would spend
        # an agent's rounds at double speed and number them 1, 3, 5.
        #
        # @return [void]
        def remember(ordinal, agent, state, status, round)
          mutex.synchronize do
            entries = history[[ordinal.to_s, agent]]
            entry = entries.find { |h| h[:state] == state && h[:round] == round }
            entry ? entry[:status] = status : entries << { state:, status:, round: }
          end
        end

        # @param subject [OpenLanes::Plans::Subject]
        # @param kind [String] see {Finishes#finish}
        # @return [void]
        def finish(subject, kind) = finishes.finish(subject, kind)

        # A requeued agent's round is handed back: the stop was a person's
        # choice, not the agent running out of turns.
        #
        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [void]
        def forget_round(job)
          ordinal = job.task.subject.feature.ordinal.to_s
          mutex.synchronize do
            history[[ordinal, job.task.agent.name]].reject! { |h| h[:state] == job.state && h[:round] == job.task.round }
          end
          finished_plans.delete(ordinal)
        end

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
      end
    end
  end
end
