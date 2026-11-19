# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      class Handle
        # How a {Handle} is asked to compact its session (W28), and how the
        # request is refused once the invocation is over.
        module Compacting
          # Why a compaction asked of an invocation that is over is refused.
          TOO_LATE = "the agent finished before it could be compacted"

          # @return [OpenLanes::Execution::Executor::Compaction, nil] the latest
          #   compaction asked for
          def compaction = @mutex.synchronize { @compaction }

          # Ask for the session to be compacted (W28): INTERRUPT, so the agent
          # leaves a resume note and ends its turn, and SIGKILL after +grace+
          # seconds if it has not. {Executor#call} then compacts the session and
          # carries it on. Asked twice while under way, it is the same request.
          #
          # @param model [String, nil] what the session carries on in
          # @param grace [Integer] seconds before the agent is made to stop
          # @return [OpenLanes::Execution::Executor::Compaction]
          def compact!(model: nil, grace: Control::GRACE)
            process = @mutex.synchronize do
              return @compaction if @compaction && !@compaction.finished?

              @compaction = Compaction.new(model:)
              return @compaction.tap { it.refuse!(TOO_LATE) } if @closed

              request_compaction
            end
            stop_after(grace, process)
            @compaction
          end

          # @return [OpenLanes::Execution::Executor::Compaction, nil] the request
          #   to act on now, handed out once
          def take_compaction = @mutex.synchronize { @requested.tap { @requested = nil } }

          # The invocation is over: a request that arrives now, or one that came
          # too late to be acted on, is refused rather than left waiting.
          #
          # @return [void]
          def close!
            @mutex.synchronize do
              @closed = true
              @requested&.refuse!(TOO_LATE)
              @requested = nil
            end
          end

          private

          # Aimed at the process running now, taken before the request is
          # visible: once it is, {Executor#call} may already be compacting, and
          # an INTERRUPT or a kill sent after that would stop the resumed
          # session. Called holding the mutex.
          #
          # @return [OpenLanes::Execution::AgentProcess, nil] the process asked to stop
          def request_compaction
            child.tap do
              Control.write(control, Control::INTERRUPT) if control
              @requested = @compaction
            end
          end

          # @param grace [Integer]
          # @param process [OpenLanes::Execution::AgentProcess, nil] the one asked to stop
          # @return [void]
          def stop_after(grace, process)
            return unless process

            Thread.new do
              sleep(grace) if grace.positive?
              process.terminate if process.equal?(child)
            end
          end
        end
      end
    end
  end
end
