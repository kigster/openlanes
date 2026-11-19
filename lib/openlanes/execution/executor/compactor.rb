# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # A person's compaction (W28), once the agent has stopped for it: its
      # session is compacted with `/compact`, then resumed with
      # {Prompt#continuation}, on the model the request names or the one it
      # was on, under the same handle. The request is answered once the
      # continuation has started, which is the moment a person can see it
      # carry on, or refused with the reason it could not be.
      class Compactor
        # @param launcher [OpenLanes::Execution::Executor::Launcher]
        # @param invocations [OpenLanes::Execution::Executor::Invocation]
        # @param drain [OpenLanes::Execution::Executor::Drain]
        def initialize(launcher:, invocations:, drain:)
          @launcher = launcher
          @invocations = invocations
          @drain = drain
        end

        # @param compaction [OpenLanes::Execution::Executor::Compaction]
        # @param attempt [OpenLanes::Execution::Executor::Attempt]
        # @return [Process::Status, nil] how the continuation ended; nil when
        #   there was none, and the agent's own stop stands
        def carry_on(compaction, attempt, &)
          killed = attempt.handle.killed
          if killed
            compaction.refuse!("#{attempt.agent.name} was stopped first (#{killed})")
            return nil
          end

          on = attempt.with(profile: attempt.profile.with(model: compaction.model || attempt.profile.model))
          why = uncompactable(attempt) || compact(on)
          return refuse(compaction, attempt, why) if why

          continue(compaction, attempt, on, &)
        end

        # A compaction whose `/compact` or continuation could not even be
        # started is refused before the error goes on up, so the person who
        # asked is answered rather than left waiting on a thread that died.
        #
        # @param compaction [OpenLanes::Execution::Executor::Compaction]
        # @param agent [OpenLanes::Agents::Agent]
        # @return [Process::Status, nil] what the block returned
        def settling(compaction, agent)
          yield
        rescue StandardError => e
          compaction.refuse!("could not compact #{agent.name}: #{e.message}") unless compaction.finished?
          raise
        end

        private

        # The agent gets its round back to start afresh unless it was stopped.
        #
        # @return [nil]
        def refuse(compaction, attempt, why)
          compaction.refuse!("could not compact #{attempt.agent.name}: #{why}", restart: !attempt.handle.killed)
          nil
        end

        # @return [String, nil] why the session cannot be compacted, if it cannot
        def uncompactable(attempt)
          adapter = attempt.profile.adapter
          return "#{adapter.name} cannot resume a session" unless adapter.compacts?

          "no session id to resume" unless attempt.handle.session
        end

        # `/compact` sent into the stopped session.
        #
        # @param on [OpenLanes::Execution::Executor::Attempt] on the model it carries on in
        # @return [String, nil] why it failed, nil when it compacted
        def compact(on)
          handle = on.handle
          argv = @invocations.argv(on, prompt: on.profile.adapter.compact_prompt, resume: handle.session, slash_commands: true)
          status = @drain.drain(@launcher.launch(argv, on), on.sessions, handle)
          return "the agent was stopped during /compact (#{handle.killed})" if handle.killed

          CompactReply.failure(status, on.sessions.current)
        end

        # The continuation, started in the compacted session.
        #
        # @return [Process::Status]
        def continue(compaction, attempt, on, &)
          handle = attempt.handle
          Control.write(handle.control, "")
          prompt = Prompt.new(agent: attempt.agent,
            subject: attempt.subject,
            root: attempt.root,
            profile: attempt.profile,
            control: handle.control).continuation
          child = @launcher.launch(@invocations.argv(on, prompt:, resume: handle.session), on, &)
          compaction.done!(CompactReply.note(attempt, on.profile.model, compaction))
          @drain.drain(child, attempt.sessions, handle)
        end
      end
    end
  end
end
