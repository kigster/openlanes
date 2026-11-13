# frozen_string_literal: true

module OpenLanes
  module Agents
    # A cheaper model for a small change: an agent's `small_diff:` frontmatter,
    # e.g. `small_diff: { under_lines: 300, model: sonnet, effort: medium }`.
    #
    # It lives in the agent's own definition because which model an agent
    # runs on is a routing fact, and those belong in `agents/*.md`. Read by
    # {Profile.resolve}, below every override a person typed.
    #
    # @!attribute [r] under_lines
    #   @return [Integer] a diff of fewer changed lines than this is small
    # @!attribute [r] model
    #   @return [String, nil]
    # @!attribute [r] effort
    #   @return [String, nil]
    SmallDiff = Data.define(:under_lines, :model, :effort) do
      # @param lines [Integer, nil] insertions plus deletions; nil when unknown
      # @return [Boolean] whether a diff of +lines+ is small; never when unknown
      def applies?(lines) = !lines.nil? && lines < under_lines
    end

    class SmallDiff
      class << self
        # @param value [Hash, nil] the frontmatter's `small_diff:`
        # @param path [String] for the error message
        # @return [OpenLanes::Agents::SmallDiff, nil]
        # @raise [OpenLanes::Error] when it is not a mapping with a positive `under_lines`
        def parse(value, path)
          return nil if value.nil?

          settings = value.is_a?(Hash) ? value.transform_keys(&:to_s) : {}
          new(under_lines: under_lines(settings["under_lines"], path),
            model:       settings["model"]&.to_s,
            effort:      effort(settings["effort"], path))
        end

        private

        # @return [Integer]
        def under_lines(lines, path)
          return lines if lines.is_a?(Integer) && lines.positive?

          raise OpenLanes::Error,
            "#{File.basename(path)}: small_diff needs a positive under_lines, e.g. " \
            "`small_diff: { under_lines: 300, model: sonnet }`"
        end

        # @return [String, nil]
        def effort(value, path)
          return nil if value.nil?
          return value.to_s if Adapters.effort?(value.to_s)

          raise OpenLanes::Error,
            "#{File.basename(path)}: small_diff effort #{value.to_s.inspect} is not one of " \
            "#{Adapters::EFFORTS.join(", ")}"
        end
      end
    end
  end
end
