# frozen_string_literal: true

module OpenLanes
  module Supervision
    # How the {Supervisor} stops its children (S1): TERM to each one's
    # process group, a wait of up to +grace+ seconds, a second TERM, then KILL
    # to whatever is still there. Each child is reaped as it goes, so none is left a
    # zombie behind a supervisor that is about to exit.
    class Shutdown
      # Seconds a KILLed child gets to be reaped.
      KILLED_WITHIN = 5

      # Seconds after the second TERM: the engine's own KILL to its agents'
      # groups, and a margin.
      HURRIED_WITHIN = Execution::Child::TERM_GRACE + 5

      # Seconds between looks.
      POLL = 0.2

      # @param slots [Array<OpenLanes::Supervision::Slot>] the running ones are stopped
      # @param host [OpenLanes::Supervision::Host]
      def initialize(slots, host:)
        @slots = slots.select(&:running?)
        @host = host
      end

      # @param grace [Numeric] seconds after TERM before KILL
      # @yieldreturn [Boolean] true to stop waiting and KILL now: a second stop
      # @return [void]
      def call(grace:, &now)
        signal("TERM", @slots)
        wait_out(grace, &now)
        hurry
        signal("KILL", @slots.select(&:running?))
        wait_out(KILLED_WITHIN) { false }
      end

      private

      # A second TERM is the engine's second Ctrl-C: it raises, and the
      # engine's `at_exit` KILLs every agent's process group. A KILL to the
      # engine's own group would reach none of them, and leave them running.
      #
      # @return [void]
      def hurry
        late = @slots.select(&:running?)
        return if late.empty?

        signal("TERM", late)
        wait_out(HURRIED_WITHIN) { false }
      end

      # @param name [String]
      # @param slots [Array<OpenLanes::Supervision::Slot>]
      # @return [void]
      def signal(name, slots) = slots.each { @host.signaller.call(name, -it.pid) }

      # @param seconds [Numeric]
      # @yieldreturn [Boolean] whether to stop waiting early
      # @return [void]
      def wait_out(seconds)
        clock = @host.clock
        deadline = clock.monotonic + seconds
        until @slots.none?(&:running?) || clock.monotonic >= deadline || yield
          @slots.each { settle(it) }
          clock.sleep(POLL) if @slots.any?(&:running?)
        end
      end

      # @param slot [OpenLanes::Supervision::Slot]
      # @return [void]
      def settle(slot)
        slot.pid = nil if slot.running? && @host.waiter.call(slot.pid)
      end
    end
  end
end
