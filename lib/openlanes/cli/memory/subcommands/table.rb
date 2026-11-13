# frozen_string_literal: true

module OpenLanes
  module CLI
    module Memory
      # Rows as left-aligned columns, the header first: what `memory list`
      # and `memory inbox` both print on STDOUT.
      module Table
        module_function

        # @param rows [Array<Array<String>>] the header, then one row each
        # @return [String]
        def render(rows)
          widths = rows.first.each_index.map { |i| rows.map { it[i].size }.max }
          "#{rows.map { |cells| cells.zip(widths).map { |cell, width| cell.ljust(width) }.join("  ").rstrip }.join("\n")}\n"
        end
      end
    end
  end
end
