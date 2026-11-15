# frozen_string_literal: true

require "yaml"

module OpenLanes
  module Arbitration
    # The arbitrator's answer to a running agent that asked for more time
    # than the engine grants on its word (E2), read from the fenced
    # `extension` block its answer ends with. A block that cannot be read is
    # refused by name, as a {Ruling} is: a guessed grant is time nobody gave.
    #
    # It is not a {Ruling}: nothing is recorded under `rulings`, posted on a
    # pull request or moved. The engine only moves a clock.
    #
    # @!attribute [r] seconds
    #   @return [Integer] what it grants; 0 when it declines
    # @!attribute [r] reason
    #   @return [String]
    TimeRuling = Data.define(:seconds, :reason) do
      # @return [Boolean] whether any time was granted
      def granted? = seconds.positive?
    end

    class TimeRuling
      # The fenced block, with `extension` as its info string.
      BLOCK = /^```extension[ \t]*\n(.*?)^```[ \t]*$/m

      # What `decision:` may say.
      DECISIONS = %w[grant decline].freeze

      class << self
        # @param text [String, nil] the adapter's final text
        # @return [TimeRuling]
        # @raise [Ruling::Missing, Ruling::Ambiguous, Ruling::IllegalOutcome]
        def parse(text)
          blocks = text.to_s.scan(BLOCK).map(&:first)
          raise Ruling::Missing, "the answer has no ```extension block" if blocks.empty?
          raise Ruling::Ambiguous, "the answer has #{blocks.size} ```extension blocks; one is read" if blocks.size > 1

          from(load(blocks.first))
        end

        private

        # @return [Hash]
        def load(yaml)
          data = YAML.safe_load(yaml)
          raise Ruling::Ambiguous, "the extension block is not a YAML mapping" unless data.is_a?(Hash)

          data.transform_keys(&:to_s)
        rescue Psych::SyntaxError => e
          raise Ruling::Ambiguous, "the extension block is not YAML: #{e.message}"
        end

        # @return [TimeRuling]
        def from(data)
          decision = data["decision"].to_s
          raise Ruling::IllegalOutcome, "an extension cannot rule #{decision.inspect}" unless DECISIONS.include?(decision)

          new(seconds: decision == "grant" ? granted(data["minutes"]) : 0, reason: data["reason"].to_s.strip)
        end

        # @return [Integer] seconds
        def granted(minutes)
          Plans::Estimate.seconds(minutes) or
            raise Ruling::IllegalOutcome, "a grant needs `minutes:` above zero, not #{minutes.inspect}"
        end
      end
    end
  end
end
