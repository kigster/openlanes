# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Lanes < Step
        # The copilot's commands on one lane that stop no process themselves:
        # `/stop` signals the plan's agents and takes it out of the run, and
        # `/restart` puts a lane that lost its agent back in.
        class Copilot < Step
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
            raise OpenLanes::Error, "#{ordinal} is not on this run's board: no agent is working it and it is not in scope" if keys.empty? && !in_run?(ordinal)

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
          # @raise [OpenLanes::Error] when an agent is working it, or it is not on this node's board
          def restart_plan(ordinal)
            ordinal = ordinal.to_s
            runner.add_plan(restartable!(ordinal).feature.ordinal)
            mutex.synchronize { history.delete_if { |(plan, _), _| plan == ordinal } }
            finished_plans.delete(ordinal)
            wake!
          end

          private

          def restartable!(ordinal)
            working = running.select { plan_of(it) == ordinal }.map { it.task.agent.name }
            raise OpenLanes::Error, "#{ordinal} already has an agent: #{working.join(", ")}" unless working.empty?

            subject = fresh_by(Plans::Ordinal.parse(ordinal))
            return subject if subject && ours?(ordinal, subject)

            raise OpenLanes::Error, "#{ordinal} is not on this node's board"
          end

          # In this run, or dropped from it, and not claimed by another machine.
          def ours?(ordinal, subject) = (in_run?(ordinal) || runner.dropped?(ordinal)) && !runner.foreign?(subject)
        end
      end
    end
  end
end
