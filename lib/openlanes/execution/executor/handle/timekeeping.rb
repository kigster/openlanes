# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      class Handle
        # A {Handle}'s clock: set once the child exists, extended or held
        # from the keyboard before or after that, and spoken through so no
        # warning lands on top of a line for the agent.
        #
        # Seconds granted before there is a clock wait in +@pending+ under
        # the handle's +@mutex+, the one `docs/thread-safety.md` names.
        module Timekeeping
          # @return [OpenLanes::Execution::Clock, nil]
          attr_reader :clock

          # The clock, once {Executor#call} has started it. Seconds granted
          # before then (a round given more time, E1) go onto it now rather
          # than being dropped for want of a clock.
          #
          # @param clock [OpenLanes::Execution::Clock, nil]
          # @return [void]
          def clock=(clock)
            @mutex.synchronize do
              @clock = clock
              clock&.extend!(@pending) if @pending&.positive?
              @pending = nil
            end
          end

          # @return [Integer, nil]
          def remaining = clock&.remaining

          # @return [Symbol, nil]
          def phase = clock&.phase

          # More time on the clock, or on the clock to come.
          #
          # @param seconds [Integer]
          # @return [Boolean] false when the clock had already stopped the agent
          def extend!(seconds)
            clock = nil
            granted = @mutex.synchronize do
              next (clock = @clock).extend!(seconds) if @clock

              @pending = @pending.to_i + seconds
              true
            end
            restart!(deadline: Executor.deadline(clock)) if granted && clock
            granted
          end

          # A line for the agent, through its clock so no warning lands on top
          # of it (see {Clock#say!}).
          #
          # @param text [String]
          # @return [Boolean] false with no clock running to say it through
          def say!(text) = clock&.say!(text) || false

          # At least +floor+ seconds on the clock, while the engine works out
          # whether the agent gets more (see {Clock#hold!}). The moved deadline
          # is written for a restarted engine, as an extension's is.
          #
          # @param floor [Integer] seconds
          # @return [Boolean] whether the deadline moved
          def hold!(floor)
            clock = self.clock
            moved = clock&.hold!(floor) || false
            restart!(deadline: Executor.deadline(clock)) if moved
            moved
          end
        end
      end
    end
  end
end
