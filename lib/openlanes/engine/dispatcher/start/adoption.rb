# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Start < Step
        # Take back an agent a dead engine left (B1 in plan 041), as
        # {Start#start} would have started it, except that nothing is recorded
        # as started again and no round is spent: the stage is the dead run's,
        # and it settles here like any other.
        class Adoption < Step
          # @param desk [Desk]
          # @param claims [Claims]
          # @param jobs [Jobs]
          # @param work [#call] runs a block on the job's thread, `(job, ordinal, &block)`
          def initialize(desk, claims:, jobs:, work:)
            super(desk)
            @claims = claims
            @jobs = jobs
            @work = work
          end

          # @param found [OpenLanes::Engine::Recovery::Reattach::Found]
          # @return [Array(String, String, Integer), nil] the stage, or nil when
          #   the plan could not be locked, which leaves it stranded
          def call(found)
            subject = found.subject
            ordinal = subject.feature.ordinal.to_s
            return nil unless @claims.reserve(ordinal, subject, found.agent) && @claims.lock(ordinal, subject)

            job = job_for(found)
            note(found, job, ordinal)
            job.thread = @work.call(job, ordinal) { reattach(found, job) }
            running << job
            found.key
          end

          private

          def note(found, job, ordinal)
            remember(ordinal, found.agent.name, job.state, "Started", found.round)
            UI.log("reattached", **job.task.log_fields)
            invocations[job.key] = clock.now
          end

          def job_for(found)
            subject, agent = found.subject, found.agent
            @jobs.build(runner.prepare(agent, subject, found.round, refresh: false),
              @jobs.handle(subject.feature.ordinal.to_s, agent, found.round),
              from:   found.from,
              state:  subject.status.key,
              rounds: rounds_allowed(agent, subject))
          end

          def reattach(found, job)
            runner.executor.reattach(found.agent,
              found.subject,
              restart: found.restart, handle: job.handle,
              &@jobs.progress_of(job))
          end
        end
      end
    end
  end
end
