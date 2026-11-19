# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # When an agent's clock runs out, written down for a later engine.
      module Deadline
        module_function

        # @param clock [OpenLanes::Execution::Clock]
        # @return [String] when the clock runs out, as wall-clock time, which
        #   outlives the engine where the clock's own monotonic deadline does not
        def of(clock) = (Time.now + clock.remaining).utc.iso8601
      end
    end
  end
end
