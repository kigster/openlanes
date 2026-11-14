# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Settle < Step
        # One outcome, written to both records. The engine's state file once
        # defaulted a failed round to Completed while state.json said
        # Interrupted, so the page and the plan disagreed about the same round.
        class Records < Step
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @param attempt [OpenLanes::Engine::Runner::Attempt]
          # @return [void]
          def write(job, attempt)
            outcome = attempt.status || (attempt.ok ? "Completed" : "Interrupted")
            stage(job, attempt, outcome)
            state_file&.record(plan_of(job), **state_fields(job, attempt, outcome))
          end

          private

          def state_fields(job, attempt, outcome)
            { agent: job.task.agent.name, round: job.task.round, status: outcome, exit: attempt.ok ? "ok" : attempt.note,
              ended_at: clock.now.iso8601, up: attempt.up, down: attempt.down,
              # An agent that ends before the first poll is otherwise never named here.
              **{ session: job.handle&.session }.compact }
          end

          def stage_fields(job, attempt, outcome)
            { status: outcome, to: attempt.to.to_s, finished_at: clock.now.iso8601, up: attempt.up.to_i,
              down: attempt.down.to_i, seconds: attempt.seconds.to_f.round(1), note: attempt.note.to_s,
              session: job.handle&.session }
          end

          def stage(job, attempt, outcome)
            task = job.task
            settled = fresh(task) or return
            stage!(settled, task.agent, task.round, **stage_fields(job, attempt, outcome))
          end
        end
      end
    end
  end
end
