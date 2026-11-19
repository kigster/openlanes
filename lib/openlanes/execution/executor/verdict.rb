# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # How an invocation went: killed, given up on its provider's rate limit,
      # failed, refused by its CLI, over the autonomy boundary, or completed.
      # A failed invocation still spent what it spent: a run that burned two
      # hundred thousand tokens before timing out is a different fact from one
      # that failed to authenticate and spent nothing.
      class Verdict
        # @param max_tokens [Integer, nil] the budget a :budget kill names
        def initialize(max_tokens:) = @max_tokens = max_tokens

        # @param attempt [OpenLanes::Execution::Executor::Attempt] once it has ended
        # @param status [Process::Status] how its last start ended
        # @param before [OpenLanes::Execution::Boundary::Snapshot] taken before it ran
        # @param started [Float] UI.monotonic when it was asked for
        # @return [OpenLanes::Execution::Executor::Result]
        def judge(attempt, status, before:, started:)
          handle = attempt.handle
          sessions = attempt.sessions
          return killed(attempt, started) if handle.killed
          # Ahead of the CLI's own words, which for a limit that never lifted
          # are the same "429" a reader would take for the agent's failure.
          return failure(sessions, started, note: traced(handle.throttled, attempt), pid: handle.pid, throttled: true) if handle.throttled

          note = refusal(attempt, status) || before.violation(attempt.root)
          return failure(sessions, started, note:, pid: handle.pid) if note

          spent(sessions, started, ok: true, pid: handle.pid, note: "completed#{" - #{sessions.tools} tool calls" if sessions.tools.positive?}")
        end

        # @return [OpenLanes::Execution::Executor::Result] a failure, with what it spent
        def failure(sessions, started, **fields) = spent(sessions, started, ok: false, **fields)

        # @param sessions [OpenLanes::Execution::Executor::Sessions, OpenLanes::Execution::Transcript]
        # @param started [Float]
        # @return [OpenLanes::Execution::Executor::Result]
        def spent(sessions, started, **fields)
          Result.new(up: sessions.up,
            down: sessions.down,
            tools: sessions.tools,
            subagents: sessions.spawned,
            delegated: sessions.delegated,
            cached: sessions.cached,
            seconds: UI.monotonic - started,
**fields)
        end

        # @param reason [Symbol]
        # @return [String]
        def killed_note(reason)
          case reason
          when :timeout then "timed out (killed #{Clock::GRACE}s after STOP)"
          when :budget then "token budget of #{@max_tokens} exceeded"
          when :quit then "still running after #{Control.interrupted? ? "ctrl-c" : "q"}, killed once the grace period ran out"
          else "killed by request"
          end
        end

        private

        # @return [OpenLanes::Execution::Executor::Result]
        def killed(attempt, started)
          handle = attempt.handle
          seen = "last seen #{attempt.sessions.current.activity || "starting up"}"
          spent(attempt.sessions,
            started,
            ok:     false,
            pid:    handle.pid,
            killed: handle.killed,
            note:   traced("#{killed_note(handle.killed)}, #{seen}", attempt))
        end

        # @return [String, nil] what the CLI said when it exited badly or reported an error
        def refusal(attempt, status)
          executable = attempt.profile.adapter.executable
          transcript = attempt.sessions.current
          return traced("#{executable} exited #{status.exitstatus}: #{Said.of(transcript)}", attempt) unless status.success?

          traced("#{executable} reported: #{transcript.error}", attempt) if transcript.failed?
        end

        # @return [String]
        def traced(note, attempt) = "#{note} - trace: #{attempt.trace}"
      end
    end
  end
end
