# frozen_string_literal: true

module OpenLanes
  module Execution
    # How long a clock gets when an engine takes back an agent an earlier one
    # started. The recorded deadline is wall clock, so it counts every hour
    # the machine was off or asleep: an engine down overnight took agents
    # back at zero, told them STOP and carded them "running out of time"
    # when they had barely begun.
    #
    # Two readings say whether the agent really spent that time:
    #
    # - its process's age, from {ProcessStart}: one younger than
    #   {JUST_STARTED_SECONDS} cannot have used much of anything;
    # - the tokens the dead engine saw it spend, the up and down the board
    #   shows and the state file keeps per stage: under
    #   {JUST_STARTED_TOKENS} it had done a few turns at most when that
    #   engine went away, however old its process is.
    #
    # An agent that just started gets its whole budget from now. One that
    # has been working keeps the recorded deadline, which charges it for the
    # hours it ran. With neither reading, it keeps what it had left when its
    # engine was last seen alive.
    #
    # @!attribute [r] deadline
    #   @return [Time] the deadline the dead engine recorded
    # @!attribute [r] budget
    #   @return [Integer] the agent's whole clock, in seconds
    # @!attribute [r] seen_at
    #   @return [Time, nil] the dead engine's last heartbeat
    # @!attribute [r] started
    #   @return [Time, nil] when the agent's process started
    # @!attribute [r] tokens
    #   @return [Integer, nil] up plus down, as the dead engine last recorded them
    # @!attribute [r] now
    #   @return [Time]
    Rearm = Data.define(:deadline, :budget, :seen_at, :started, :tokens, :now) do
      # Younger than this, a process has not used its budget.
      self::JUST_STARTED_SECONDS = 600

      # Fewer tokens than this (up plus down) is a few turns of work at most:
      # one turn re-sends the whole context, typically 20k to 40k tokens.
      self::JUST_STARTED_TOKENS = 100_000

      # @return [Integer] seconds on the new clock, never negative
      def seconds
        case verdict
        when :just_started then budget
        when :working then [deadline - now, 0].max.round
        else [deadline + downtime - now, 0].max.round
        end
      end

      # @return [Symbol] :just_started, :working or :unknown
      def verdict
        return :just_started if young? || idle?
        return :working if !started.nil? || !tokens.nil?

        :unknown
      end

      private

      # @return [Boolean]
      def young? = !started.nil? && now - started < self.class::JUST_STARTED_SECONDS

      # @return [Boolean]
      def idle? = !tokens.nil? && tokens < self.class::JUST_STARTED_TOKENS

      # @return [Float] seconds since the dead engine was last seen, or 0
      def downtime = seen_at ? [now - seen_at, 0].max : 0
    end
  end
end
