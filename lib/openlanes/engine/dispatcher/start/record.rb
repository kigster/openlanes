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
              started_at: clock.now.iso8601,
              cwd:        task.root,
              **states(job),
              **profile_fields(task.agent, task.subject, root: task.root))
          end

          # Where the plan was picked up, and where the round works. They
          # differ once the start renamed the folder, and {Plans::Rounds}
          # counts the round for the second: with `from` alone, an agent
          # that `starts_as` had its first round counted for no state.
          def states(job) = { from: job.from.to_s, state: job.state.to_s }

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
