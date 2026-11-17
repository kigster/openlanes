# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # The arbitrator's rulings, written by the engine from the arbitrator's
      # block (M7: the agent itself writes nothing).
      class Rulings < Section
        # @return [Array<Hash>] oldest first; empty on a plan written before rulings existed
        def rulings = read["rulings"] || []

        # @param ruling [OpenLanes::Plans::PlanState::Ruling]
        # @return [Hash] the ruling as written
        def rule!(ruling)
          record = ruling.to_json_h
          update { |data| (data["rulings"] ||= []) << record }
          record
        end
      end
    end
  end
end
