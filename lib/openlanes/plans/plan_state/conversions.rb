# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # Questions the engine rewrote into lettered choices (D9), and the ones
      # it could not. `blocked.md` keeps only the rewrite, so the agent's own
      # words live here, beside the digest that keeps a restarted run from
      # asking the model about the same text again.
      class Conversions < Section
        # @return [Array<Hash>] oldest first; empty for a plan never converted
        def conversions = read["conversions"] || []

        # @param digest [String] SHA256 of the question's body as the agent wrote it
        # @return [Boolean] whether that text was converted, or failed to be
        def converted?(digest) = conversions.any? { it["digest"] == digest }

        # @param conversion [OpenLanes::Plans::PlanState::Conversion]
        # @return [Hash] the record as written
        def conversion!(conversion)
          record = conversion.to_json_h
          update { |data| (data["conversions"] ||= []) << record }
          record
        end
      end
    end
  end
end
