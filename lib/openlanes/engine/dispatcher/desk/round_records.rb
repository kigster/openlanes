# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # The desk's positional calls onto {Recovery::Records}, which takes a
        # {Recovery::Round} rather than three loose arguments.
        class RoundRecords
          # @param records [OpenLanes::Engine::Recovery::Records]
          def initialize(records)
            @records = records
          end

          # @return [void] see {Recovery::Records#resume}
          def harness_resume(subject, agent, round, reason, last: last_line(subject, agent), phrase: nil) # rubocop:disable Metrics/ParameterLists -- Desk's contract, called positionally by the steps
            @records.resume(Recovery::Round.new(subject:, agent:, round:), reason, last:, phrase:)
          end

          # @return [OpenLanes::Plans::Ledger::Entry, nil] see {Recovery::Records#last_line}
          def last_line(subject, agent) = @records.last_line(Recovery::Round.new(subject:, agent:, round: nil))

          # @return [void] see {Recovery::Records#interrupted}
          def write_interrupted(subject, agent, round, reason)
            @records.interrupted(Recovery::Round.new(subject:, agent:, round:), reason)
          end

          # @return [void] see {Recovery::Records#stage!}
          def stage!(subject, agent, round, **)
            @records.stage!(Recovery::Round.new(subject:, agent:, round:), **)
          end
        end
      end
    end
  end
end
