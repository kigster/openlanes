# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What an invocation that spent nothing looks like: no tokens in, none
      # out, no tool call. {Result#failed_start?} and the lost-session test
      # both ask it, so the two cannot disagree.
      module Spending
        module_function

        # @param spent [#up, #down, #tools] a {Result}, a transcript or the sessions of one invocation
        # @return [Boolean] whether it spent nothing at all
        def nothing?(spent) = spent.up.to_i.zero? && spent.down.to_i.zero? && spent.tools.to_i.zero?
      end
    end
  end
end
