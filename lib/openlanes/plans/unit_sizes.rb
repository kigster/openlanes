# frozen_string_literal: true

module OpenLanes
  module Plans
    # The `**Size:**` the planner gives each unit in plan.md, read back so
    # {Agents::Profile} can match the builder to the work: a plan of small
    # units should not pay Opus at high effort for every one of them.
    #
    # A unit is a `###` heading whose first word is its id (`### B5a Split
    # dispatcher`), and its size is the first `**Size:**` bullet beneath it,
    # before the next heading. A unit without one has no size, and a plan
    # with no sized unit falls back to whatever chose the profile before.
    module UnitSizes
      # Cheapest first, so the rank of a size is its index.
      SIZES = %w[small medium large].freeze

      # `### B5a Split dispatcher`, `### F1 Board`.
      HEADING = /\A\#{3}\s+(?<id>[A-Z]+\d+[a-z]?)\b/

      # `- **Size:** large`, case and surrounding emphasis forgiven.
      SIZE = /\A\s*[-*]\s+\*\*Size:?\*\*:?\s*(?<size>\w+)/i

      # Any heading at all ends a unit.
      ANY_HEADING = /\A\#{1,6}\s/

      module_function

      # @param text [String, nil] plan.md
      # @return [Hash{String => String}] unit id → size, only for the units
      #   that name one of {SIZES}
      def parse(text)
        unit = nil
        text.to_s.each_line.with_object({}) do |line, sizes|
          unit = unit_of(line, unit)
          size = unit && !sizes.key?(unit) && line[SIZE, :size]&.downcase
          sizes[unit] = size if SIZES.include?(size)
        end
      end

      # @param line [String]
      # @param current [String, nil] the unit the line before was in
      # @return [String, nil] the unit this line is in: a unit heading starts
      #   one, any other heading ends it
      def unit_of(line, current)
        return line[HEADING, :id] if line.match?(HEADING)

        line.match?(ANY_HEADING) ? nil : current
      end

      # @param text [String, nil] plan.md
      # @return [String, nil] the largest size any unit names; nil when none does
      def largest(text) = parse(text).values.max_by { SIZES.index(it) }
    end
  end
end
