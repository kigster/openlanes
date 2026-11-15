# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What the dispatcher holds on a running invocation, so a keypress can
      # reach it: the process, its clock and its control file.
      #
      # Filled in by {#call} once the child exists. Every method tolerates the
      # gap before that, because the keyboard does not wait.
      class Handle
        include Stopping
        include Compacting

        def initialize
          @mutex = Mutex.new
          @requested = nil
          @compaction = nil
          @closed = false
        end

        # @return [OpenLanes::Execution::AgentProcess, nil] the process running now,
        #   which after a compaction is no longer the first one
        attr_accessor :child

        # @return [String, nil] the CLI's session id, once its stream named it
        attr_accessor :session

        # @return [OpenLanes::Execution::AgentProcess::Label, nil] which agent,
        #   on which plan, for the agent supervisor's files and title
        attr_accessor :label

        # @return [String, nil] the raw NDJSON trace the agent's stream is
        #   copied into, so the engine journal can name it and its offset
        attr_accessor :trace

        # @return [#call, nil] told, as a Hash, each part of what a restarted
        #   engine needs to take this invocation back (B5 in plan 041),
        #   whenever that part changes
        attr_accessor :on_restart

        # @return [String, nil] why the invocation was given up on while its
        #   provider was rate limiting it or overloaded, once it was
        attr_accessor :throttled

        # @param fields [Hash{Symbol => Object}]
        # @return [void]
        def restart!(**fields) = on_restart&.call(fields)

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
        def pid = child&.pid

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
