# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Start < Step
        # The two holds a job needs on its plan before it starts: the plan's
        # alock, and its lock file.
        class Claims < Step
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
        end
      end
    end
  end
end
