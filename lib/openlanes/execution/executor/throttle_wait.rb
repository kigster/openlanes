# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # An invocation that ended on its provider's rate limit or overload
      # waits and is started again, for as long as {Throttle::Backoff}
      # allows, inside the one attempt (plan 060.00, item 4). Its clock is
      # given the wait back, since the agent did not have that time. When
      # the limit outlasts the waiting, or somebody stops the agent while it
      # waits, {Handle#throttled} says so, and the verdict reports that
      # instead of the CLI's last words.
      class ThrottleWait
        # @param throttle [OpenLanes::Execution::Throttle::Backoff]
        # @param launcher [OpenLanes::Execution::Executor::Launcher]
        # @param invocations [OpenLanes::Execution::Executor::Invocation]
        # @param drain [OpenLanes::Execution::Executor::Drain]
        def initialize(throttle:, launcher:, invocations:, drain:)
          @throttle = throttle
          @launcher = launcher
          @invocations = invocations
          @drain = drain
        end

        # @param status [Process::Status] how the invocation just ended
        # @param attempt [OpenLanes::Execution::Executor::Attempt]
        # @param again [#call, nil] starts the invocation over as it was first
        #   started; nil when only its session can be carried on
        # @return [Process::Status] how the last start ended
        def ride_out(status, attempt, again: nil, &)
          handle = attempt.handle
          waits = @throttle.waits
          while !handle.killed && (limit = Throttle.detect(status, attempt.sessions.current))
            child = retried(Wait.new(limit:, waits:, seconds: waits.next(limit)), attempt, again, &)
            break handle.throttled ||= waits.surrender(limit) unless child

            status = @drain.drain(child, attempt.sessions, handle)
          end
          status
        end

        private

        # @return [OpenLanes::Execution::AgentProcess, nil] the start after the wait
        def retried(wait, attempt, again, &)
          wait.seconds && wait_out(wait, attempt, &) && StartAgain.new(@launcher, @invocations).call(wait.limit, attempt, again, &)
        end

        # One wait: said, given back to the clock, and sat through unless
        # somebody stops the agent meanwhile. The clock's "time was extended"
        # line is written over the control file, so a HOLD, WRAP_UP or PAUSE
        # already there is put back. And while agents are paused (W32, Redis
        # is out) the wait goes on past its own end: a pause that started an
        # agent would not be one (PR 204).
        #
        # @return [Boolean] false when the wait was cut short by a stop
        def wait_out(wait, attempt, &)
          handle = attempt.handle
          announce(wait, attempt, &)
          standing = StandingOrder.of(handle)
          handle.extend!(wait.seconds.ceil)
          Control.write(handle.control, standing) if standing
          return true if sat_through(wait.seconds, handle)

          handle.throttled = "#{wait.limit}: stopped while waiting to retry (#{wait.limit.detail})"
          false
        end

        # @return [Boolean] whether the wait ran its course
        def sat_through(seconds, handle)
          stopped = -> { handle.stopping? || Control.quit? || Control.interrupted? }
          passed = @throttle.pause(seconds, &stopped)
          passed = @throttle.pause(Throttle::Backoff::SLICE, &stopped) while passed && Control.paused?
          passed
        end

        # The wait, in the log and over the agent's own line on the board.
        #
        # @return [void]
        def announce(wait, attempt, &on_progress)
          agent = attempt.agent
          waiting = "#{wait.limit}, retry #{wait.waits.count} of #{@throttle.attempts} in #{wait.seconds.round}s"
          UI.log("#{agent.name} #{waiting} (#{wait.limit.detail})", level: :warn, plan: attempt.plan, agent: agent.name)
          shown = attempt.sessions.shown
          on_progress&.call(shown.with(activity: waiting)) if shown
        end
      end
    end
  end
end
