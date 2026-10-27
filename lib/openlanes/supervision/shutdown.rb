# frozen_string_literal: true

module OpenLanes
  module Supervision
    # How the {Supervisor} stops the whole system (S1, and B3 and C2 in plan
    # 041): INT to each child's process group and USR1 to every agent of
    # the project, a wait of up to +grace+ seconds, a second INT, then KILL
    # to whatever child is still there; last, the agents still alive get
    # what is left of the grace, then TERM. Each child is reaped as it
    # goes, so none is left a zombie behind a supervisor that is about to
    # exit.
    #
    # INT, not TERM: to the engine INT is a deliberate quit, which stops its
    # agents, while TERM ends it and leaves them for the engine that
    # replaces it. The web takes either as a stop.
    class Shutdown
      # Seconds a KILLed child gets to be reaped.
      KILLED_WITHIN = 5

      # Seconds after the second INT: the engine's own KILL to its agents'
      # groups, and a margin.
      HURRIED_WITHIN = Execution::Child::TERM_GRACE + 5

      # Seconds between looks.
      POLL = 0.2

      # @param slots [Array<OpenLanes::Supervision::Slot>] the running ones are stopped
      # @param host [OpenLanes::Supervision::Host]
      # @param sweep [AgentSweep, nil] tells and stops the agents; nil leaves them be
      def initialize(slots, host:, sweep: nil)
        @slots = slots.select(&:running?)
        @host = host
        @sweep = sweep
      end

      # @param grace [Numeric] seconds after INT before KILL, which the
      #   agents share
      # @yieldreturn [Boolean] true to stop waiting and KILL now: a second stop
      # @return [void]
      def call(grace:, &now)
        deadline = @host.clock.monotonic + grace
        signal("INT", @slots)
        @sweep&.interrupt
        wait_out(grace, &now)
        hurry
        signal("KILL", @slots.select(&:running?))
        wait_out(KILLED_WITHIN) { false }
        @sweep&.call(grace: now&.call ? 0 : [deadline - @host.clock.monotonic, 0].max)
      end

      private

      # A second INT is the engine's second Ctrl-C: it raises, and the
      # engine's `at_exit` KILLs every agent's process group. A KILL to the
      # engine's own group would reach none of them, and leave them running.
      #
      # @return [void]
      def hurry
        late = @slots.select(&:running?)
        return if late.empty?

        signal("INT", late)
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
