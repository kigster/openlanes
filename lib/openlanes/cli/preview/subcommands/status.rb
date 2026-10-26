# frozen_string_literal: true

module OpenLanes
  module CLI
    module Preview
      # `openlanes project status` — every port an app holds on this machine,
      # read from the registry, so it answers with or without Redis.
      class Status < Base
        include Registry

        desc "List the apps running on this machine: plan, process, port, pid, checkout"

        # @param options [Hash]
        # @return [void]
        def call(**options)
          quiet?(options)
          entries = registry.entries
          if entries.empty?
            UI.line("No app is running on this machine.") unless quiet?(options)
            return
          end

          rows = entries.map { |port, entry| [entry["plan"], entry["process"], port.to_s, entry["owner"].to_s, entry["root"]] }
          puts table([%w[PLAN PROCESS PORT PID CHECKOUT], *rows.sort])
        end

        private

        # @param rows [Array<Array<String>>]
        # @return [String]
        def table(rows)
          widths = rows.transpose.map { |column| column.map { it.to_s.length }.max }
          rows.map { |row| row.each_with_index.map { |cell, i| cell.to_s.ljust(widths[i]) }.join("  ").rstrip }.join("\n")
        end
      end
    end
  end
end
