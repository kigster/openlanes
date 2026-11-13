# frozen_string_literal: true

require "json"

module OpenLanes
  module Execution
    # Reads one invocation's raw NDJSON trace back after the run. The
    # arbitrator writes no file, so its final answer is its whole work: the
    # engine parses a ruling out of it, and the live evals score the same
    # text. One reader for both, so an eval reads the answer the engine
    # would act on.
    module Trace
      module_function

      # @param path [String, nil] the trace an executor handle named
      # @return [String] the last `result` event's text; empty when there
      #   is no trace, no result line, or a line that is not JSON
      def answer(path)
        return "" unless path && File.exist?(path)

        File.foreach(path).filter_map { JSON.parse(it)["result"] if it.include?("\"result\"") }.last.to_s
      rescue JSON::ParserError
        ""
      end
    end
  end
end
