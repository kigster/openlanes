# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # Sets one agent going on one plan: holds taken ({Claims}), folder renamed,
      # round recorded ({Record}), and the executor called ({Invocation}) on a
      # thread of its own. A stopped rebase is started as a job that resolves it.
      class Start < Step
        # The desk, and the steps a plan's folder ({Rename}) and review round ({Settle}) go to.
        def initialize(desk, rename:, settle:)
          super(desk)
          @rename = rename
          @claims = Claims.new(desk)
          @jobs = Jobs.new(desk)
          @launch = Launch.new(desk, jobs: @jobs, settle:)
          @record = Record.new(desk)
          @invocation = Invocation.new(desk, session: Session.new(desk), jobs: @jobs)
          @adoption = Adoption.new(desk, claims: @claims, jobs: @jobs, work: method(:work))
          @conflicts = Conflicts.new(desk, claims: @claims, jobs: @jobs, rebase: method(:start_rebase))
        end

        # @return [Boolean, nil] false when another run took the plan's lock
        #   first, nil when an agent outside openlanes holds the plan
        def start(agent, subject)
          # Before the rename, so a plan held outside openlanes is left as it was (W31).
          return nil unless @claims.reserve(subject.feature.ordinal.to_s, subject, agent)

          # The round is counted before the rename, while the folder still
          # says the state it is counted in: `state.json` names a visit by
          # the plan's moves, and a rename on start is one.
          launch(agent, subject, from: subject.status.key, round: next_round(subject, agent))
        end

        # @return [Array(String, String, Integer), nil] see {Adoption#call}
        def adopt(found) = @adoption.call(found)

        # @return [void] see {Conflicts#call}
        def resolve_conflict(upkeep, conflict) = @conflicts.call(upkeep, conflict)

        private

        # Locked before anything is recorded and before the thread, so the next
        # tick sees it. Until the thread that releases it exists, a failure does.
        def launch(agent, subject, from:, round:)
          ordinal = subject.feature.ordinal.to_s
          owed = false
          subject = locked(agent, subject, ordinal) or return false
          @launch.open(agent, subject, from)
          owed = true
          begin_work(@launch.job(agent, subject, from:, round:), ordinal)
        rescue StandardError
          locks.release(ordinal) if owed && !runner.dry_run?
          locks.unreserve(ordinal)
          raise
        end

        # The folder renamed, then its lock taken: the subject under its new name, or nil.
        def locked(agent, subject, ordinal)
          subject = @rename.rename_on_start(subject, agent) unless runner.dry_run?
          subject if @claims.lock(ordinal, subject)
        end

        def begin_work(job, ordinal)
          return start_rebase(job, ordinal) && true if job.task.refresh&.conflicted?

          invoke = @invocation.for(job)
          @record.started(job, job.task.round)
          job.thread = work(job, ordinal, &invoke)
          running << job
          true
        end

        # The job's thread: its result is the block's value or error; the lock goes when it ends.
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

        # A job that resolves a stopped rebase (D10): no round is spent.
        def start_rebase(job, ordinal)
          @jobs.rebasing(job)
          job.thread = Thread.new do
            Thread.current.report_on_exception = false
            job.result = @jobs.resolve(job, ordinal)
          end
          running << job
        end
      end
    end
  end
end
