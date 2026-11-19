# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # Reads a running session to its end, and kills it the moment it
      # crosses its token budget or the grace period after `q`.
      class Drain
        # @param max_tokens [Integer, nil] budget per invocation; nil is unmetered
        # @param fresh_budget [Boolean] count only new tokens, leaving out cache reads
        def initialize(max_tokens:, fresh_budget:)
          @max_tokens = max_tokens
          @fresh_budget = fresh_budget
        end

        # @param child [OpenLanes::Execution::AgentProcess, #each_chunk]
        # @param sessions [OpenLanes::Execution::Executor::Sessions]
        # @param handle [OpenLanes::Execution::Executor::Handle]
        # @return [Process::Status]
        def drain(child, sessions, handle)
          child.each_chunk do |out|
            sessions.current.push(out)
            abort_if_over(sessions, handle)
          end
          status = child.wait
          sessions.current.finish
          status
        end

        # The token budget crossed, or the grace period after `q` spent. Both go
        # through the handle so the kill is the same kill a keypress makes.
        #
        # @param sessions [OpenLanes::Execution::Executor::Sessions]
        # @param handle [OpenLanes::Execution::Executor::Handle]
        # @return [void]
        def abort_if_over(sessions, handle)
          if @max_tokens&.positive? && spent(sessions) > @max_tokens
            handle.kill!(grace: 0, reason: :budget)
          elsif Control.overdue?
            handle.kill!(grace: 0, reason: :quit)
          end
        end

        private

        # @return [Integer] what counts against the budget
        def spent(sessions) = @fresh_budget ? sessions.fresh : sessions.up + sessions.down
      end
    end
  end
end
