# frozen_string_literal: true

module OpenLanes
  module Execution
    class AgentProcess
      # The agent supervisors this process started and has not seen end,
      # and what becomes of them when it exits. {AgentProcess} extends it.
      module Registry
        # @param base [Class]
        # @return [void]
        def self.extended(base)
          base.instance_variable_set(:@live, [])
          base.instance_variable_set(:@mutex, Mutex.new)
          base.instance_variable_set(:@reattachable, false)
        end

        # @return [Array<AgentProcess>] started and not yet ended
        def live = @mutex.synchronize { @live.dup }

        # TERM to every agent supervisor still running; each one finishes
        # the stop by itself, so the engine does not wait for it.
        #
        # @return [void]
        def terminate_all = live.each { it.kill("TERM") }

        # Said by an engine that can take its agents back: from then on its
        # agents outlive a crash or a TERM, and are stopped on the way out
        # only after a deliberate quit (B2 in plan 041). Anything else that
        # runs an agent stops it whenever it exits.
        #
        # @return [void]
        def reattachable! = @mutex.synchronize { @reattachable = true }

        # For specs: back to stopping every agent on exit, as a process that
        # never said {#reattachable!} does.
        #
        # @return [void]
        def reset! = @mutex.synchronize { @reattachable = false }

        # What `at_exit` does.
        #
        # @param quit [Boolean] whether the exit was a deliberate quit
        # @return [void]
        def exiting(quit: Control.quit?)
          terminate_all if quit || !@mutex.synchronize { @reattachable }
        end

        # @param process [AgentProcess]
        # @return [void]
        def forget(process) = @mutex.synchronize { @live.delete(process) }

        # @param process [AgentProcess]
        # @return [AgentProcess]
        def track(process)
          @mutex.synchronize do
            @at_exit ||= at_exit { exiting }
            @live << process
          end
          process
        end
      end
    end
  end
end
