# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # The agent until it ends: its provider's rate limits waited out, a
      # lost session started again fresh, and every compaction asked for
      # carried on. Its clock is stopped and its control file let go however
      # it ends.
      class Supervision
        # What `claude -p --resume <id>` prints for an id it has no session for,
        # in the directory it was run from (2.1.x): this line on stderr, then a
        # `result` event with `is_error`, zero turns and zero tokens, exit 1.
        SESSION_MISSING = /No conversation found with session ID/

        # @param drain [OpenLanes::Execution::Executor::Drain]
        # @param throttling [OpenLanes::Execution::Executor::ThrottleWait]
        # @param compactor [OpenLanes::Execution::Executor::Compactor]
        def initialize(drain:, throttling:, compactor:)
          @drain = drain
          @throttling = throttling
          @compactor = compactor
        end

        # @param child [OpenLanes::Execution::AgentProcess, #each_chunk] the first start
        # @param attempt [OpenLanes::Execution::Executor::Attempt] with its clock
        # @param restarts [OpenLanes::Execution::Executor::Restarts]
        # @return [Process::Status]
        def supervise(child, attempt, restarts = Restarts.new, &)
          handle = attempt.handle
          # Before {#lost_session}, which reads a 429 that spent nothing as a
          # session gone and would throw away one that is still there.
          status = @throttling.ride_out(@drain.drain(child, attempt.sessions, handle), attempt, again: restarts.again, &)
          compactions(fresh_start(status, attempt, restarts, &), attempt, &)
        ensure
          handle.close!
          attempt.clock.stop
          Control.release(handle.control)
        end

        # Whether a resumed invocation failed because its session is gone,
        # rather than at anything it did, and what to say about it. The message
        # is the sure sign; a failure that spent nothing and called no tool is
        # taken as the same thing, because a CLI that rewords the message must
        # still not cost the round. That also catches an auth error or a
        # network drop at start-up, so the line the CLI printed goes into the
        # log beside the retry. A rate limit or an overload never gets here:
        # {ThrottleWait#ride_out} waits those out first, session intact.
        #
        # @param status [Process::Status]
        # @param transcript [OpenLanes::Execution::Transcript]
        # @return [String, nil] why the session counts as lost, nil when it does not
        def lost_session(status, transcript)
          return nil if status.success? && !transcript.failed?

          said = [transcript.error, *transcript.plain].map(&:to_s).reject(&:empty?)
          return "not found" if said.any? { SESSION_MISSING.match?(it) }
          return nil unless quiet?(transcript)

          "failed before spending anything (#{said.empty? ? "exit #{status.exitstatus}" : said.last.lines.first.strip[0, 200]})"
        end

        private

        # A resumed session that turned out to be gone, started again fresh.
        #
        # @return [Process::Status]
        def fresh_start(status, attempt, restarts, &)
          handle = attempt.handle
          return status unless restarts.resume && !handle.killed && !handle.throttled

          lost = lost_session(status, attempt.sessions.current)
          return status unless lost

          announce(attempt, "session #{restarts.resume} #{lost}")
          @throttling.ride_out(@drain.drain(restarts.relaunch.call, attempt.sessions, handle), attempt, again: restarts.relaunch, &)
        end

        # @return [void]
        def announce(attempt, why)
          name = attempt.agent.name
          UI.log("#{why}, starting #{name} fresh", level: :warn, plan: attempt.plan, agent: name)
        end

        # @return [Process::Status] how the last continuation ended
        def compactions(status, attempt, &)
          while (compaction = attempt.handle.take_compaction)
            resumed = @compactor.settling(compaction, attempt.agent) { @compactor.carry_on(compaction, attempt, &) }
            status = @throttling.ride_out(resumed, attempt, &) if resumed
          end
          status
        end

        # @return [Boolean] whether the session spent nothing and called no tool
        def quiet?(transcript) = Executor.spent_nothing?(transcript)
      end
    end
  end
end
