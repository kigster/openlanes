# frozen_string_literal: true

module OpenLanes
  module Execution
    # The seconds a stop gives agents to leave their resume notes (S7, and
    # C3 in plan 041): {Control::GRACE}, which the supervisor's and
    # `openlanes stop`'s waits are built on. `$OPENLANES_SHUTDOWN_GRACE` is
    # its one override; the supervisor's children inherit it, so every
    # process of one system waits the same.
    module ShutdownGrace
      # Seconds, when nothing overrides it.
      DEFAULT = 60

      # The environment variable that overrides it.
      VARIABLE = "OPENLANES_SHUTDOWN_GRACE"

      # A value that is not a whole number of seconds, zero or more, is
      # refused with a warning rather than taken as zero: a typo must not
      # turn a graceful stop into a KILL.
      #
      # @param env [Hash{String => String}]
      # @param warn [#call] where the refusal is said
      # @return [Integer]
      def self.from(env, warn: Kernel.method(:warn))
        value = env[VARIABLE]
        return DEFAULT if value.nil? || value.strip.empty?

        seconds = Integer(value.strip, 10, exception: false)
        return seconds if seconds && !seconds.negative?

        warn.call("openlanes: #{VARIABLE}=#{value.inspect} is not a whole number of seconds; using #{DEFAULT}")
        DEFAULT
      end
    end
  end
end
