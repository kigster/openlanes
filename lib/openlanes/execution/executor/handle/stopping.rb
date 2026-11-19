# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      class Handle
        # How a {Handle} is asked to stop: through its control file, now or as
        # soon as there is one, and by killing its process group.
        module Stopping
          # @return [String, nil]
          attr_reader :control

          # The control file, once {Executor#call} has registered it. A stop
          # asked for before then is written the moment it exists, so an agent
          # still starting up when Stop All came is not left running.
          #
          # @param path [String, nil]
          # @return [void]
          def control=(path)
            @mutex.synchronize do
              @control = path
              Control.write(path, Control::STOP) if path && @stop_requested
            end
          end

          # Stop at the next step, now or as soon as there is a control file.
          #
          # @return [void]
          def request_stop!
            @mutex.synchronize do
              @stop_requested = true
              Control.write(@control, Control::STOP) if @control
            end
          end

          # @return [Symbol, nil] why the process was killed, once it was
          attr_reader :killed

          # Whether anybody has asked this agent to stop: a kill, a stop asked
          # of the handle, or STOP or INTERRUPT written into its control file.
          # An agent waiting out a rate limit has no process to read that file,
          # so the wait reads it instead.
          #
          # @return [Boolean]
          def stopping?
            return true if @killed || @mutex.synchronize { @stop_requested }

            control ? File.read(control).start_with?(Control::STOP, Control::INTERRUPT) : false
          rescue SystemCallError
            false
          end

          # STOP, a grace period, then {AgentProcess#terminate}: TERM and KILL to the
          # agent's whole process group, and its pipe closed, so the invocation
          # ends even when a tool the agent started is what hangs. The grace is
          # what lets an agent mid-write finish the line.
          #
          # @param grace [Integer] seconds
          # @param reason [Symbol] :key, :timeout, :budget or :quit
          # @return [void]
          def kill!(grace: 15, reason: :key)
            @killed ||= reason
            Control.write(control, Control::STOP) if control
            sleep(grace) if grace.positive?
            child&.terminate
          end
        end
      end
    end
  end
end
