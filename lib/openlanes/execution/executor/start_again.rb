# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # The start after a wait. A start that spent nothing has nothing to
      # carry on, so it is made again as it was. One that had been working is
      # resumed in its own session and told why it was paused, which keeps
      # what it had read and done; where the CLI cannot resume, the round
      # starts over, as a failed attempt's next round would have.
      class StartAgain
        # @param launcher [OpenLanes::Execution::Executor::Launcher]
        # @param invocations [OpenLanes::Execution::Executor::Invocation]
        def initialize(launcher, invocations)
          @launcher = launcher
          @invocations = invocations
        end

        # @param limit [OpenLanes::Execution::Throttle::Limit]
        # @param attempt [OpenLanes::Execution::Executor::Attempt]
        # @param again [#call, nil] starts the invocation over as it was first started
        # @return [OpenLanes::Execution::AgentProcess, nil] nil when there is
        #   neither a session to carry on nor a way to start over
        def call(limit, attempt, again, &)
          handle = attempt.handle
          resumable = handle.session && attempt.profile.adapter.resumes?
          return refuse(limit, handle) unless resumable || again

          # The clock's "time was extended" line, written for the wait, is
          # cleared. A HOLD or WRAP_UP sent during the wait is not: the start
          # below is the first process that can read it.
          Control.write(handle.control, "") unless StandingOrder.of(handle)
          return again.call if again && (unspent?(attempt.sessions.current) || !resumable)

          @launcher.launch(@invocations.argv(attempt, prompt: Throttle.carry_on(limit), resume: handle.session), attempt, &)
        end

        private

        # @return [Boolean] whether the failed start spent nothing
        def unspent?(failed) = Executor.spent_nothing?(failed)

        # @return [nil]
        def refuse(limit, handle)
          handle.throttled = "#{limit}: no session to carry on, and nothing to start again (#{limit.detail})"
          nil
        end
      end
    end
  end
end
