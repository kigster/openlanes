# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What an invocation that spent nothing looks like: no tokens in, none
      # out, no tool call. {Result#failed_start?} and the lost-session test
      # both ask it, so the two cannot disagree.
      module Spending
        module_function

        # The three counts on their own, for the keyword form `main`'s
        # `Executor.spent_nothing?(up:, down:, tools:)` took before the cut.
        Counts = Data.define(:up, :down, :tools)

        # @param spent [#up, #down, #tools, nil] a {Result}, a transcript or the
        #   sessions of one invocation; nil when the counts come as keywords
        # @param counts [Hash{Symbol => Integer}] `up:`, `down:` and `tools:`, all three
        # @return [Boolean] whether it spent nothing at all
        def nothing?(spent = nil, **counts)
          spent ||= Counts.new(**counts)
          spent.up.to_i.zero? && spent.down.to_i.zero? && spent.tools.to_i.zero?
        end
      end
    end
  end
end
