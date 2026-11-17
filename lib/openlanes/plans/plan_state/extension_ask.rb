# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # The harness asking a person for more time or another round (E1), as
      # {PlanState#ask_extension!} receives it. +limit+ is "time" or "rounds".
      ExtensionAsk = Data.define(:agent, :state, :round, :limit, :at) do
        # @param number [Integer]
        # @param moves [Integer] the plan's move count when asked
        # @return [Hash] in the key order `state.json` has always carried
        def to_json_h(number, moves)
          { "number" => number, "agent" => agent, "state" => state.to_s, "round" => Integer(round), "limit" => limit,
            "asked_at" => at.iso8601, "moves" => moves }
        end
      end
    end
  end
end
