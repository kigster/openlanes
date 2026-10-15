# frozen_string_literal: true

module OpenLanes
  module Coverage
    # `lcov.info`: one `SF:` … `end_of_record` block per source file, each
    # carrying `LF:` (instrumented lines) and `LH:` (lines hit).
    #
    # There is no total record, and the per-file percentages must not be
    # averaged: a ten-line file at 0% and a thousand-line file at 100% are
    # 99%, not 50%. The counts are summed instead. A block without `LF`/`LH`
    # is counted from its `DA:` lines, which is what those two summarise.
    module Lcov
      module_function

      # @param text [String]
      # @return [Array(Integer, Integer)] covered, relevant
      # @raise [OpenLanes::Coverage::Malformed] when text is present but holds
      #   no `SF:` record
      def parse(text)
        records = text.split(/^end_of_record\s*$/).grep(/^SF:/)
        raise Malformed, "no SF: records" if records.empty? && !text.strip.empty?

        records.map { tally(it) }.transpose.map(&:sum).then { it.empty? ? [0, 0] : it }
      end

      # @param record [String] one file's block
      # @return [Array(Integer, Integer)]
      def tally(record)
        found = record[/^LF:(\d+)/, 1]
        hit = record[/^LH:(\d+)/, 1]
        return [Integer(hit), Integer(found)] if found && hit

        hits = record.scan(/^DA:\d+,(-?\d+)/).flatten.map { Integer(it) }
        [hits.count(&:positive?), hits.size]
      end
    end
  end
end
