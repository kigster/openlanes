# frozen_string_literal: true

module OpenLanes
  module Engine
    module Steps
      # Yes at most once per interval, and at once the first time it is
      # asked. Monotonic, so a wall-clock change neither skips a pass nor
      # repeats one.
      class Interval
        # @param seconds [Numeric]
        def initialize(seconds)
          @seconds = seconds
          @last = nil
        end

        # @return [Boolean] whether a pass is due; a yes starts the next interval
        def due?
          now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          return false if @last && now - @last < @seconds

          @last = now
          true
        end
      end
    end
  end
end
