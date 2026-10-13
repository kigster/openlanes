# frozen_string_literal: true

module OpenLanes
  # The smallest Markdown reader that covers what plan folders actually hold.
  # No CommonMark ambitions: it needs to find a GFM table and split its rows.
  module Markdown
    module_function

    # Split a table row into stripped cells.
    #
    # @param row [String] a line beginning, and usually ending, with `|`
    # @return [Array<String>]
    def cells(row)
      row.strip.sub(/\A\|/, "").sub(/\|\z/, "").split(/(?<!\\)\|/).map(&:strip)
    end

    # @param row [String]
    # @return [Boolean] whether this is a `|---|:--:|` alignment row
    def delimiter_row?(row)
      parsed = cells(row)
      !parsed.empty? && parsed.all? { |c| c.match?(/\A:?-+:?\z/) }
    end

    # Every GFM table in the document, in order.
    #
    # @param text [String]
    # @return [Array<Hash{Symbol => Array}>] `{header:, rows:}`
    def tables(text)
      lines = text.to_s.lines(chomp: true)
      found = []
      index = 0

      while index < lines.length
        head = lines[index]
        rule = lines[index + 1]

        unless head&.strip&.start_with?("|") && rule&.strip&.start_with?("|") && delimiter_row?(rule)
          index += 1
          next
        end

        body = []
        cursor = index + 2
        while cursor < lines.length && lines[cursor].strip.start_with?("|")
          body << cells(lines[cursor])
          cursor += 1
        end

        found << { header: cells(head), rows: body }
        index = cursor
      end

      found
    end
  end
end
