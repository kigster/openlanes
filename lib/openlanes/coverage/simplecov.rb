# frozen_string_literal: true

require "json"

module OpenLanes
  module Coverage
    # SimpleCov's `coverage/.resultset.json`: per command (RSpec, and any
    # suite merged in), per file, one hit count per source line, `nil` where a
    # line is not code.
    #
    # Not `.last_run.json`: that one truncates to two decimals and is written
    # only after a fully successful run (plan decision 3). The resultset is
    # already filtered by the project's SimpleCov filters, so every file in it
    # counts. It does not record `:nocov:` blocks, so this figure can come out
    # lower than SimpleCov's own, never higher.
    #
    # {.lines_by_file} is public so `bin/coverage-changed` (PR #27), which
    # judges each changed file, merges runs the same way the gate does.
    module Simplecov
      module_function

      # @param text [String]
      # @return [Array(Integer, Integer)] covered, relevant
      # @raise [OpenLanes::Coverage::Malformed]
      # @raise [JSON::ParserError]
      def parse(text)
        relevant = lines_by_file(text).values.flatten.compact
        [relevant.count(&:positive?), relevant.size]
      end

      # Every command's counts merged line by line: a line hit by any run is
      # covered, and a line is relevant when any run says it is code.
      #
      # @param text [String] the resultset
      # @return [Hash{String => Array<Integer, nil>}] by the path as recorded
      # @raise [OpenLanes::Coverage::Malformed]
      # @raise [JSON::ParserError]
      def lines_by_file(text)
        runs = JSON.parse(text)
        raise Malformed, "expected a mapping of command name to its run" unless runs.is_a?(Hash)

        runs.each_with_object({}) do |(command, run), merged|
          files = run.is_a?(Hash) && run["coverage"]
          raise Malformed, "#{command} has no coverage mapping" unless files.is_a?(Hash)

          files.each { |path, entry| merged[path] = merge(merged[path] || [], counts(path, entry)) }
        end
      end

      # SimpleCov 0.18+ writes `{"lines": [...]}`; older versions the bare
      # array. A non-integer count (`"ignored"`) is not code.
      #
      # @return [Array<Integer, nil>]
      def counts(path, entry)
        lines = entry.is_a?(Hash) ? entry["lines"] : entry
        raise Malformed, "#{path} has no line counts" unless lines.is_a?(Array)

        lines.map { it.is_a?(Integer) ? it : nil }
      end

      # @return [Array<Integer, nil>]
      def merge(into, counts)
        Array.new([into.size, counts.size].max) do |index|
          a, b = into[index], counts[index]
          a.nil? && b.nil? ? nil : a.to_i + b.to_i
        end
      end
    end
  end
end
