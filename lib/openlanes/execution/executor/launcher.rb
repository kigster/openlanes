# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # Starts one session's process, or takes back one a restarted engine
      # left running, reads it into a transcript, and arms the clock it runs
      # against.
      class Launcher
        # @param spawn [#call] `argv, chdir:, env:, label:` → an {AgentProcess}
        def initialize(spawn:) = @spawn = spawn

        # Start one session's process and the transcript that reads it. Every
        # session of an invocation shares its trace file, which is opened for
        # appending, so a compacted run reads back as one stream.
        #
        # @param argv [Array<String>]
        # @param attempt [OpenLanes::Execution::Executor::Attempt]
        # @return [OpenLanes::Execution::AgentProcess]
        def launch(argv, attempt, &)
          child = @spawn.call(argv, chdir: attempt.root, env: Launcher.environment(attempt.profile.adapter), label: attempt.handle.label)
          follow(child, attempt, argv:, &)
        end

        # What the adapter adds to the child's environment, plus
        # `AGENT_PARENT_ID`. The engine claims each plan folder in alock
        # before the job starts; without a parent, alock reads the agent as
        # a stranger and refuses every `acquire` inside the folder, so
        # 004.00 in laser-cutter could not even write its `blocked.md`. As
        # the engine's child it may claim files there, while a pair partner
        # on the same file and anyone outside are still refused.
        #
        # @param adapter [OpenLanes::Adapters::Base]
        # @return [Hash{String => String}]
        def self.environment(adapter) = adapter.environment.merge(Locking.child_environment)

        # Read +child+ into a new transcript under the attempt's handle. Only
        # an {AgentProcess} can be taken back by a restarted engine, so only
        # one is reported to {Handle#restart!}.
        #
        # @param child [OpenLanes::Execution::AgentProcess, #each_chunk]
        # @param attempt [OpenLanes::Execution::Executor::Attempt]
        # @param argv [Array<String>] what +child+ was started with; empty for
        #   one taken back after a restart
        # @return [OpenLanes::Execution::AgentProcess, #each_chunk] +child+
        def follow(child, attempt, argv: [], &on_progress)
          handle = attempt.handle
          attempt.sessions << transcript(attempt, argv, &on_progress).tap { it.pid = child.pid }
          handle.child = child
          handle.restart!(process: child.restart) if child.respond_to?(:restart)
          child
        end

        # @param handle [OpenLanes::Execution::Executor::Handle]
        # @param seconds [Numeric]
        # @return [OpenLanes::Execution::Clock] started, and handed to +handle+
        def start_clock(handle, seconds:)
          clock = Clock.new(seconds:, control: handle.control, on_expire: -> { handle.kill!(grace: 0, reason: :timeout) })
          handle.clock = clock
          clock.start
          clock
        end

        # The clock a reattached agent runs on: its whole budget when it had
        # barely begun, what is left of the recorded deadline when it has been
        # working, and otherwise what it had when its engine was last seen.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @param restart [Hash{String => Object}]
        # @param budget [Integer] the agent's whole clock
        # @return [Integer] seconds
        def rearm(agent, restart, budget:)
          rearm = Rearm.new(deadline: Time.iso8601(restart.fetch("deadline")),
            budget:,
            seen_at: restart["seen_at"]&.then { Time.iso8601(it) },
            started: ProcessStart.of(restart.dig("process", "pid")),
            tokens: restart["tokens"],
            now: Time.now)
          UI.log("reattached clock: #{rearm.verdict.to_s.tr("_", " ")}, #{(rearm.seconds / 60.0).round} minutes", agent: agent.name)
          rearm.seconds
        end

        private

        # @return [OpenLanes::Execution::Transcript]
        def transcript(attempt, argv, &on_progress)
          handle = attempt.handle
          attempt.profile.adapter.transcript(trace: attempt.trace, argv:) do |progress|
            handle.session ||= progress.session
            on_progress&.call(attempt.sessions.carry(progress))
          end
        end
      end
    end
  end
end
