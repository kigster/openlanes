# frozen_string_literal: true

module OpenLanes
  # A time source, so a spec can move time instead of waiting for it.
  #
  # Not to be confused with {OpenLanes::Execution::Clock}, the timeout timer
  # with a thread of its own; inside `Execution` a bare `Clock` means that
  # one, so code there writes `OpenLanes::Clock` in full.
  module Clock
    # The real clock.
    module System
      module_function

      # @return [Time]
      def now = Time.now

      # @return [Float] seconds on a clock no wall-clock change can move
      def monotonic = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

      # @param seconds [Numeric]
      # @return [void]
      def sleep(seconds) = Kernel.sleep(seconds)
    end

    # A clock that only moves when told to. {#sleep} advances rather than
    # blocks, so a loop that waits on it runs at once and still sees time pass.
    # Shared between threads in the stress spec, hence the mutex.
    class Fake
      # @param now [Time]
      def initialize(now: Time.utc(2026, 1, 1))
        @now = now
        @monotonic = 0.0
        @mutex = Mutex.new
      end

      # @return [Time]
      def now = @mutex.synchronize { @now }

      # @return [Float]
      def monotonic = @mutex.synchronize { @monotonic }

      # @param seconds [Numeric]
      # @return [self]
      def advance(seconds)
        @mutex.synchronize do
          @now += seconds
          @monotonic += seconds
        end
        self
      end

      # @param seconds [Numeric]
      # @return [void]
      def sleep(seconds) = advance(seconds)
    end
  end
end
