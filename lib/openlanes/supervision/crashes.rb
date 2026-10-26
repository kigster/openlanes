# frozen_string_literal: true

module OpenLanes
  module Supervision
    # One child's recent crashes (S1): how long to wait before the next
    # restart, and when to stop restarting. Three crashes inside five minutes
    # is a child that will not come up, and restarting it forever only fills
    # the log.
    class Crashes
      # Crashes inside {WINDOW} after which the child is given up on.
      LIMIT = 3

      # Seconds a crash counts for.
      WINDOW = 300

      # The longest wait before a restart, in seconds.
      LONGEST = 30

      # @param clock [#monotonic]
      # @param limit [Integer]
      # @param window [Numeric]
      def initialize(clock: OpenLanes::Clock::System, limit: LIMIT, window: WINDOW)
        @clock = clock
        @limit = limit
        @window = window
        @times = []
      end

      # @return [self]
      def record
        @times << @clock.monotonic
        self
      end

      # @return [Boolean]
      def exhausted? = recent.size >= @limit

      # @return [Integer] seconds before the next restart: 1, 2, 4, … up to {LONGEST}
      def delay = [2**[recent.size - 1, 0].max, LONGEST].min

      # @return [String] why the child was given up on
      def reason = "#{recent.size} crashes in #{Title.duration(@window.to_i)}"

      private

      # @return [Array<Float>]
      def recent = @times.select { @clock.monotonic - it < @window }
    end
  end
end
