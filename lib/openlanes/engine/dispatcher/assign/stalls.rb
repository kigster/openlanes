# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Assign < Step
        # Agents held by their own failed starts (plan 065.00): the request a
        # parked one raises, and the clause that names them in the idle line,
        # so none is left out of the run with nobody told.
        class Stalls < Step
          # An agent parked at the cap asks a person for a round.
          #
          # @param agent [OpenLanes::Agents::Agent]
          # @param subject [OpenLanes::Plans::Subject]
          # @return [void]
          def ask(agent, subject)
            return unless failed_start_hold(subject, agent) == :capped

            _, last = failed_streak(subject, agent)
            extensions.stalled(subject.feature.path, agent.name, subject.status.key, next_round(subject, agent), after: last)
          end

          # @param subjects [Array<OpenLanes::Plans::Subject>]
          # @return [String, nil] each held agent, its plan and what lets it go
          def reason(subjects)
            held = subjects.flat_map { |subject| held_on(subject) }
            "failed starts: #{held.join("; ")}" unless held.empty?
          end

          private

          def held_on(subject)
            Agents::Routing.offer(runner.agents, subject.status, subject).filter_map do |agent|
              why = WHY[failed_start_hold(subject, agent)] or next
              "#{subject.feature.ordinal} #{agent.name} (#{why})"
            end
          end

          # What the idle line says of each hold.
          WHY = { capped:      "#{Desk::FailedStarts::CAP} in a row; grant it a round to retry",
                  backing_off: "retrying after a backoff" }.freeze
          private_constant :WHY
        end
      end
    end
  end
end
