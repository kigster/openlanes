# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Start < Step
        # The executor call a job's thread runs: who comes next, who the
        # partners are, which session carries on, and the verifier's app
        # around it all.
        class Invocation < Step
          # @param desk [Desk]
          # @param session [Session]
          # @param jobs [Jobs]
          def initialize(desk, session:, jobs:)
            super(desk)
            @session = session
            @jobs = jobs
          end

          # Asked before this round's own stage is written, which would
          # otherwise be the latest one {Session} finds.
          #
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @return [Proc] the call, for the job's thread
          def for(job)
            task = job.task
            fields = fields_for(job)
            -> { around(task) { runner.executor.call(task.agent, task.subject, **fields, &@jobs.progress_of(job)) } }
          end

          private

          def fields_for(job)
            task = job.task
            { root: task.root, round: task.round, successor: successor(task.agent, task.subject), handle: job.handle,
              partners: partners(task.agent, task.subject), resume: @session.resumption_for(task, job.from) }
          end

          def around(task, &invoke)
            verifier?(task.agent) ? runner.verification.around(task, task.subject, &invoke) : invoke.call
          end

          def successor(agent, subject)
            return unless agent.advances_to && Plans::STATUS_BY_KEY.key?(agent.advances_to)

            Agents::Routing.offer(runner.agents, Plans::STATUS_BY_KEY.fetch(agent.advances_to), subject).first&.name
          end

          # Each member of a pair is told who the others are, so the executor
          # can name them beside the plan's mailbox. A partner routing would
          # never start is not a partner.
          def partners(agent, subject)
            team = runner.agents.team_for(Lifecycle::Resync::Dirs.target(subject))
            Agents::Routing.filter(team, subject) - [agent]
          end
        end
      end
    end
  end
end
