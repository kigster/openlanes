# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # Sets one agent going on one plan: the plan's locks taken, its folder
      # renamed where the agent `starts_as`, its checkout prepared, the round
      # recorded as Started, and the executor called on a thread of its own.
      # A stopped rebase is started the same way, as a job that resolves it.
      class Start < Step
        # @param desk [Desk]
        # @param rename [Rename]
        # @param settle [Settle]
        def initialize(desk, rename:, settle:)
          super(desk)
          @rename = rename
          @settle = settle
        end

        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Boolean, nil] false when another run took the plan's lock
        #   first, nil when an agent outside openlanes holds the plan
        def start(agent, subject)
          ordinal = subject.feature.ordinal.to_s
          round = history[[ordinal, agent.name]].count { |h| h[:state] == subject.status.key } + 1
          from = subject.status.key
          # Before the rename, so a plan somebody outside openlanes holds is
          # left exactly as they had it (W31).
          return nil unless reserve(ordinal, subject, agent)

          subject = rename_on_start(subject, agent) unless runner.dry_run?
          # The lock says the folder is in use, so nothing renames it while the
          # agent holds its path. It is taken before anything is recorded as
          # started, since another run can win it between the check and here,
          # and before the thread, so the next tick already sees it; it goes
          # when the last agent in the plan does, however that agent went.
          return false unless lock(ordinal, subject)

          # Once a round, by whichever reviewer opens it: the rest start at 👀.
          if from == :ready_for_review && agent.phase.to_s == REVIEW_PHASE && !runner.dry_run?
            runner.reviews.started(subject)
            end_replacements(ordinal)
          end
          finishes.unfinish(subject)

          release_owed = true
          # A checkout another agent is working in is never moved under it.
          alone = running.none? { plan_of(it) == ordinal }
          task = runner.prepare(agent, subject, round, refresh: alone, hold: rebases.hold(ordinal))
          handle = Execution::Executor::Handle.new
          handle.on_restart = restart_recorder(ordinal, agent, round)
          # A round a person gave more time to (E1) starts with it.
          bonus = runner.dry_run? ? 0 : extensions.take_seconds(subject.feature.path, agent.name, subject.status.key)
          handle.extend!(bonus) if bonus.positive?
          job = Job.new(key: "#{ordinal}/#{agent.name}",
            task:,
            handle:,
            started_at: UI.monotonic,
            from:,
            state: subject.status.key,
            up: 0,
            down: 0,
            subagents: 0,
            frame: 0,
            rounds: rounds_allowed(agent, subject))
          if task.refresh&.conflicted?
            start_rebase(job, ordinal)
            release_owed = false
            return true
          end
          job.message = task.refresh.summary if task.refresh&.kind == :pending
          if agent.advances_to && Plans::STATUS_BY_KEY.key?(agent.advances_to)
            successor = Agents::Routing.offer(runner.agents, Plans::STATUS_BY_KEY.fetch(agent.advances_to), subject).first&.name
          end
          # Each member of a pair is told who the others are, so the executor
          # can name them beside the plan's mailbox. A partner routing would
          # never start is not a partner.
          team = runner.agents.team_for(Lifecycle::Resync::Dirs.target(subject))
          partners = Agents::Routing.filter(team, subject) - [agent]
          # Asked before this round's own stage is written, which would
          # otherwise be the latest one it finds.
          resume = resumption_for(task, from)
          remember(ordinal, agent.name, job.state, "Started", round)
          stage!(subject,
            agent,
            round,
            reset:      true,
            status:     "Started",
            from:       from.to_s,
            started_at: clock.now.iso8601,
            cwd:        task.root,
            **profile_fields(agent, subject, root: task.root))
          state_file&.record(ordinal,
            agent:      agent.name,
            round:,
            status:     "Started",
            state:      from.to_s,
            model:      model_for(agent, subject, root: task.root),
            file:       agent.ledger.first,
            started_at: clock.now.iso8601)
          feed.append(:plan_assigned, plan: ordinal, agent: agent.name, round:)
          UI.log("started", **task.log_fields)
          invocations[job.key] = clock.now
          runner.events.record(:agent_started, **event_fields(job))
          job.thread = work(job, ordinal) do
            invoke = lambda {
              runner.executor.call(agent,
                subject,
                root:      task.root,
                round:,
                successor:,
                handle:,
                partners:,
                resume:,
                &progress_of(job))
            }
            verifier?(agent) ? runner.verification.around(task, subject, &invoke) : invoke.call
          end
          release_owed = false
          running << job
          true
        rescue StandardError
          # Failed before the thread that releases it existed.
          locks.release(ordinal) if release_owed && !runner.dry_run?
          locks.unreserve(ordinal)
          raise
        end

        # Take back an agent a dead engine left (B1 in plan 041), as {#start}
        # would have started it, except that nothing is recorded as started
        # again and no round is spent: the stage is the dead run's, and it
        # settles here like any other.
        #
        # @param found [OpenLanes::Engine::Recovery::Reattach::Found]
        # @return [Array(String, String, Integer), nil] the stage, or nil when
        #   the plan could not be locked, which leaves it stranded
        def adopt(found)
          subject = found.subject
          agent = found.agent
          ordinal = subject.feature.ordinal.to_s
          return nil unless reserve(ordinal, subject, agent) && lock(ordinal, subject)

          task = runner.prepare(agent, subject, found.round, refresh: false)
          handle = Execution::Executor::Handle.new
          handle.on_restart = restart_recorder(ordinal, agent, found.round)
          job = Job.new(key: "#{ordinal}/#{agent.name}",
            task:,
            handle:,
            started_at: UI.monotonic,
            from: found.from,
            state: subject.status.key,
            up: 0,
            down: 0,
            subagents: 0,
            frame: 0,
            rounds: rounds_allowed(agent, subject))
          remember(ordinal, agent.name, job.state, "Started", found.round)
          UI.log("reattached", **task.log_fields)
          invocations[job.key] = clock.now
          job.thread = work(job, ordinal) { runner.executor.reattach(agent, subject, restart: found.restart, handle:, &progress_of(job)) }
          running << job
          found.key
        end

        # Rebase a waiting pull request's branch onto `main` in its plan's
        # checkout (U3). Only the scheduling is the dispatcher's: a stop on
        # conflicts becomes a rebaser job, as a pre-run rebase's does
        # (D10), and what follows either way is the keeper's. A plan that
        # cannot be started now, with every slot taken or somebody in it, is
        # asked about on the next sweep.
        #
        # @param upkeep [OpenLanes::Engine::Upkeep::Keeper]
        # @param conflict [OpenLanes::Engine::Upkeep::Conflict]
        # @return [void]
        def resolve_conflict(upkeep, conflict)
          ordinal = conflict.ordinal
          resolver = runner.agents.find(Rebase::RESOLVER)
          return UI.log("conflicts left on PR ##{conflict.number}: no #{Rebase::RESOLVER} is defined", level: :warn, plan: ordinal) unless resolver

          subject = runner.tree.find(ordinal)
          if subject.nil? || running.size >= runner.jobs || untouchable.include?(ordinal) || !runner.claim(subject)
            return upkeep.later(conflict)
          end
          return upkeep.later(conflict) unless reserve(ordinal, subject, resolver)

          unless lock(ordinal, subject)
            locks.unreserve(ordinal)
            return upkeep.later(conflict)
          end

          begin
            task = runner.prepare(resolver, subject, 1, hold: rebases.hold(ordinal))
          rescue StandardError
            locks.release(ordinal)
            raise
          end
          return conflict_job(task, conflict) if task.refresh&.conflicted?

          begin
            said(upkeep.rebased(conflict, task.checkout, task.refresh), ordinal)
          ensure
            locks.release(ordinal)
          end
        end

        private

        def_delegators :@rename, :rename_on_start
        def_delegators :@settle, :end_replacements

        # The job's thread: its result is what the block returned, or the
        # error it raised, and the plan's lock goes when it ends.
        #
        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @param ordinal [String]
        # @return [Thread]
        def work(job, ordinal)
          Thread.new do
            Thread.current.report_on_exception = false
            job.result = begin
              yield
            rescue StandardError => e
              e
            ensure
              locks.release(ordinal) unless runner.dry_run?
            end
          end
        end

        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [Proc] what the executor tells of the agent's progress, onto the job
        def progress_of(job)
          lambda do |progress|
            job.up = progress.up
            job.down = progress.down
            job.subagents = progress.subagents
            job.running = progress.running
            job.context = progress.context
            job.message = progress.message || progress.activity
            job.history = Board::Row.remember(job.history || [], job.message)
            job.journal = progress.journal
          end
        end

        # @param ordinal [String]
        # @param agent [OpenLanes::Agents::Agent]
        # @param round [Integer]
        # @return [Proc, nil] writes the restart context into the stage (B5 in
        #   plan 041); nil without a state file, as under a dry run
        def restart_recorder(ordinal, agent, round)
          return nil unless state_file

          ->(fields) { state_file.restart(ordinal, agent: agent.name, round:, **fields) }
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
              locks.release(ordinal)
            end
          end
          running << job
        end

        # The plan's alock, taken before its first job starts. Refused, the
        # plan's Redis claim goes back too, so another machine may take it.
        #
        # @param ordinal [String]
        # @param subject [OpenLanes::Plans::Subject]
        # @param agent [OpenLanes::Agents::Agent]
        # @return [Boolean] whether the job may start
        def reserve(ordinal, subject, agent)
          locks.reserve(ordinal, subject.feature.path, "openlanes: #{agent.name} on #{ordinal}")
          true
        rescue PlanLocks::Refused => e
          UI.log("not started: #{e.message}", level: :warn, plan: ordinal, agent: agent.name)
          runner.release(ordinal)
          refusals << ordinal
          false
        end

        # @param ordinal [String]
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Boolean] whether this run now holds the plan's lock
        def lock(ordinal, subject)
          locks.hold(ordinal, subject.feature.path) unless runner.dry_run?
          true
        rescue Plans::Lock::Held => e
          UI.log("lock lost: #{e.message}", level: :warn, plan: ordinal)
          false
        end

        # The session this round carries on (M1): the previous round's, when
        # its CLI can resume one, the plan has not moved since, and it ran in
        # this round's checkout. Either way the log says which and why, since
        # an agent that suddenly knows or forgets everything is otherwise a
        # mystery.
        #
        # @param task [OpenLanes::Engine::Runner::Task]
        # @param state [Symbol] the state the plan was in when dispatched
        # @return [String, nil] the session id to resume, nil to start fresh
        def resumption_for(task, state)
          return nil if runner.dry_run?

          adapter = adapter_of(task.agent, task.subject)
          unless adapter.resumes?
            UI.log("fresh session: #{adapter.name} cannot resume one", **task.log_fields)
            return nil
          end

          decision = Plans::PlanState.for(task.subject.feature.path)
                                     .resumption(agent: task.agent.name, state:, root: task.root, adapter: adapter.name)
          UI.log(decision.resume? ? "resuming session #{decision.session}: #{decision.reason}" : "fresh session: #{decision.reason}",
            **task.log_fields)
          decision.session
        rescue OpenLanes::Error => e
          UI.log("fresh session: state.json unreadable: #{e.message}", level: :warn, **task.log_fields)
          nil
        end

        # @return [void]
        def conflict_job(task, conflict)
          job = Job.new(key: "#{conflict.ordinal}/#{task.agent.name}",
            task:,
            handle:     Execution::Executor::Handle.new,
            started_at: UI.monotonic,
            from:       task.subject.status.key,
            state:      task.subject.status.key,
            up:         0,
            down:       0,
            subagents:  0,
            frame:      0,
            sweep:      conflict)
          start_rebase(job, conflict.ordinal)
        end

        # @param report [OpenLanes::Engine::Upkeep::Report]
        # @param ordinal [String]
        # @return [void]
        def said(report, ordinal) = UI.log(report.note, level: report.ok == false ? :warn : :info, plan: ordinal)
      end
    end
  end
end
