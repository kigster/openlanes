# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Settle < Step
        # Rounds that ended because something other than the agent ended them:
        # the harness, a kill, a timeout, a quit, or a crash.
        class Stops < Step
          # @param ordinal [String]
          # @return [String, nil] why the harness stopped the plan's agents, if it did
          def stopped_for(ordinal)
            return "claim lost to another machine" if fenced.include?(ordinal)

            "discarded by a person" if discarding.key?(ordinal)
          end

          # An agent stopped because its plan was discarded or taken by another
          # machine: what it left is about to be thrown away, or is no longer
          # this node's to judge, so the harness signs nothing for it.
          #
          # @return [OpenLanes::Engine::Runner::Attempt]
          def stopped_by_harness(job, base, why)
            task = job.task
            subject = fresh(task)
            if subject
              harness_resume(subject, task.agent, task.round, why, phrase: job.message)
              write_interrupted(subject, task.agent, task.round, why)
            end
            remember(plan_of(job), task.agent.name, job.state, "Interrupted", task.round)
            base.with(ok: false, status: "Interrupted", note: why)
          end

          # @param result [OpenLanes::Execution::Executor::Result]
          # @return [String]
          def reason_for(result)
            case result.killed
            when :key then "killed by harness after #{KILL_GRACE}s grace"
            when :timeout then "timed out, killed #{Execution::Clock::GRACE}s after STOP"
            when :quit then "interrupted, killed #{Execution::Control::GRACE}s after #{Execution::Control.interrupted? ? "ctrl-c" : "q"}"
            else Execution::Control.interrupted? ? "interrupted by ctrl-c" : "no closing ledger line"
            end
          end

          # @return [OpenLanes::Engine::Runner::Attempt]
          def crashed(job, base, error)
            line = error.message.lines.first.to_s.strip
            fresh(job.task)&.then { harness_resume(it, job.task.agent, base.round, line, phrase: job.message) }
            remember(base.ordinal, base.agent, job.state, "Interrupted", base.round)
            base.with(ok: false, note: line)
          end

          # @return [String] how many rounds the agent has left, after its status
          def retry_note(agent, entry)
            left = rounds_for(agent) - entry.round
            left.positive? ? "#{entry.status}; #{left} round#{"s" unless left == 1} left" : "#{entry.status}; no rounds left"
          end
        end
      end
    end
  end
end
