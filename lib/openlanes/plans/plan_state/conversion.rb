# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # One question the engine rewrote into lettered choices (D9), or tried
      # to: +digest+ is SHA256 of +original+, +outcome+ "converted" or "rejected".
      Conversion = Data.define(:question, :digest, :original, :model, :outcome, :note, :at) do
        # @param note [String, nil] why it was rejected
        # @param at [Time]
        def initialize(note: nil, at: Time.now, **) = super

        # @return [Hash] in the key order `state.json` has always carried
        def to_json_h
          { "question" => Integer(question), "digest" => digest, "original" => original, "at" => at.iso8601,
            "model" => model, "outcome" => outcome, "note" => note }.compact
        end
      end
    end
  end
end
