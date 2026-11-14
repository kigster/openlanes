# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Start < Step
        # Everything that says a round started: the desk's history, the
        # plan's state.json stage, the run's state file, the feed, the log
        # and the event log.
        class Record < Step
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @param round [Integer]
          # @return [void]
          def started(job, round)
            remember(plan_of(job), job.task.agent.name, job.state, "Started", round)
            stage(job, round)
            record_state(job, round)
            announce(job, round)
          end

          private

          def stage(job, round)
            task = job.task
            stage!(task.subject,
              task.agent,
              round,
              reset:      true,
              status:     "Started",
              from:       job.from.to_s,
              started_at: clock.now.iso8601,
              cwd:        task.root,
              **profile_fields(task.agent, task.subject, root: task.root))
          end

          def announce(job, round)
            feed.append(:plan_assigned, plan: plan_of(job), agent: job.task.agent.name, round:)
            UI.log("started", **job.task.log_fields)
            invocations[job.key] = clock.now
            runner.events.record(:agent_started, **event_fields(job))
          end

          def record_state(job, round)
            task = job.task
            state_file&.record(plan_of(job),
              agent:      task.agent.name,
              round:,
              status:     "Started",
              state:      job.from.to_s,
              model:      model_for(task.agent, task.subject, root: task.root),
              file:       task.agent.ledger.first,
              started_at: clock.now.iso8601)
          end
        end
      end
    end
  end
end
