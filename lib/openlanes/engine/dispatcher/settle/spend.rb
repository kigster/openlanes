# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Settle < Step
        # What a job's result says it spent, read through literal readers. A
        # result that cannot say (an exception, a failed app start) spent 0 of
        # each, as before; a computed method name read each field once, and
        # was the one A8 hit in the dispatcher.
        Spend = Data.define(:up, :down, :subagents, :delegated, :seconds) do
          # @param result [OpenLanes::Execution::Executor::Result, Exception, Object]
          # @return [Spend]
          def self.of(result)
            new(up: result.respond_to?(:up) ? result.up : 0,
              down: result.respond_to?(:down) ? result.down : 0,
              subagents: result.respond_to?(:subagents) ? result.subagents : 0,
              delegated: result.respond_to?(:delegated) ? result.delegated : 0,
              seconds: result.respond_to?(:seconds) ? result.seconds : 0)
          end
        end
      end
    end
  end
end
