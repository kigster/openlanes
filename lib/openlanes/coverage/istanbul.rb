# frozen_string_literal: true

require "json"

module OpenLanes
  module Coverage
    # Istanbul's `coverage-summary.json` (the `json-summary` reporter):
    # `total.lines.covered` over `total.lines.total`.
    #
    # `pct` is never read. It is floored to two decimals, and istanbul writes
    # 100 for a total of zero and `"Unknown"` for a blank summary, neither of
    # which is a figure the gate can stand behind.
    module Istanbul
      module_function

      # @param text [String]
      # @return [Array(Integer, Integer)] covered, relevant
      # @raise [OpenLanes::Coverage::Malformed]
      # @raise [JSON::ParserError]
      def parse(text)
        lines = JSON.parse(text).dig("total", "lines") if text.strip.start_with?("{")
        raise Malformed, "no total.lines" unless lines.is_a?(Hash)

        covered, total = lines.values_at("covered", "total")
        raise Malformed, "total.lines needs whole-number covered and total" unless [covered, total].all?(Integer)

        [covered, total]
      end
    end
  end
end
