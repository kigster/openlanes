# frozen_string_literal: true

module OpenLanes
  module Execution
    # The advisory clock one invocation runs against.
    #
    # It never terminates the agent on its own. It writes into the control file
    # the agent polls: a warning ten and five minutes out, a wrap-up request at
    # one, STOP at zero. Only a process still alive {GRACE} seconds after STOP
    # is killed, and that is the executor's act on this clock's say-so, so the
    # agent has every chance to write its ledger line first.
    #
    # `now` is injectable so the moments can be tested without sleeping.
    class Clock
      # Seconds before the deadline, and what the control file says then.
      # A moment already in the past when the clock starts is skipped: a five
      # minute agent told "10 minutes left" at t=0 has been lied to.
      WARNINGS = [
        [600, "WARN: 10 minutes left"],
        [300, "WARN: 5 minutes left"],
        [60, "WRAP_UP: 1 minute left, write to disk now"]
      ].freeze

      # Seconds after STOP before {#on_expire} fires.
      GRACE = 60

      # @param seconds [Integer] the budget
      # @param control [String] the invocation's control file
      # @param on_expire [Proc] called once, GRACE seconds after STOP
      # @param now [Proc] a monotonic clock reading
      def initialize(seconds:, control:, on_expire:, now: -> { UI.monotonic })
        @control = control
        @on_expire = on_expire
        @now = now
        @mutex = Mutex.new
        arm(seconds)
      end

      # @return [Integer] whole seconds left, floored at zero
      def remaining = [@deadline - @now.call, 0].max.round

      # @return [Symbol] :calm, :warned, :wrap_up, :stopped or :expired
      attr_reader :phase

      # Evaluate every moment once. Idempotent within a phase.
      #
      # @return [void]
      def tick
        @mutex.synchronize do
          next if paused

          left = @deadline - @now.call
          WARNINGS.each do |before, text|
            next if @fired.include?(before) || left > before

            @fired << before
            Control.write(@control, text)
            @phase = before == 60 ? :wrap_up : :warned
          end
          if left <= 0 && !@fired.include?(:stop)
            @fired << :stop
            Control.write(@control, Control::STOP)
            @phase = :stopped
          end
          if @fired.include?(:stop) && !@fired.include?(:expired) && left <= -GRACE
            @fired << :expired
            @phase = :expired
            @on_expire.call
          end
        end
      end

      # @return [self]
      def start
        @thread ||= Thread.new do
          Thread.current.report_on_exception = false
          loop do
            tick
            break if phase == :expired

            sleep(1)
          end
        end
        self
      end

      # Waits out an expiry under way before killing the thread. {#tick}
      # holds the mutex while {#on_expire} runs, and that is the kill: a
      # thread killed inside it, between TERM and KILL, once left a
      # grandchild that ignored TERM running after the attempt had ended.
      #
      # @return [void]
      def stop
        thread = @mutex.synchronize do
          @closed = true
          @thread.tap { @thread = nil }
        end
        thread&.kill
      end

      # Ten more minutes, or however many. The file tells the agent how long
      # it now has, so one told "5 minutes left" does not wrap up on the old
      # deadline, and every moment is re-armed against the new one.
      #
      # Refused once STOP is out or the clock is stopped: that agent is
      # exiting, and time given to it would reach nobody.
      #
      # @param seconds [Integer]
      # @return [Boolean] whether the time reached a clock still running
      def extend!(seconds)
        @mutex.synchronize do
          next false if @closed || %i[stopped expired].include?(@phase)

          @deadline += seconds
          @fired = WARNINGS.map(&:first).select { |before| before >= @deadline - @now.call }
          @phase = :calm
          Control.write(@control, "#{Control::WARN}: #{((@deadline - @now.call) / 60.0).round} minutes left, time was extended")
          true
        end
      end

      private

      # While agents are paused (W32) the clock stands still: no warning
      # overwrites the PAUSE in the agent's file, and on resume the deadline
      # moves on by as long as the pause lasted, so a paused agent is never
      # stopped for time it spent waiting.
      #
      # @return [Boolean] whether this tick is skipped
      def paused
        if Control.paused?
          @paused_at ||= @now.call
          return true
        end
        if @paused_at
          @deadline += @now.call - @paused_at
          @paused_at = nil
        end
        false
      end

      # @param seconds [Integer]
      # @return [void]
      def arm(seconds)
        @deadline = @now.call + seconds
        @fired = WARNINGS.map(&:first).select { |before| before >= seconds }
        @phase = :calm
      end
    end
  end
end
