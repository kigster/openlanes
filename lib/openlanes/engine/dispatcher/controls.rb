# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # What a person does to one running agent from a view: kill it, give it
      # time, requeue or compact it, change its model, or change how many run.
      class Controls
        # @param desk [Desk]
        def initialize(desk)
          @desk = desk
        end

        # STOP, {KILL_GRACE} seconds, SIGKILL, on a thread so the tick is not
        # held for fifteen seconds.
        #
        # @param key [String] a row's key
        # @return [void]
        def kill(key)
          job = @desk.job(key) or return
          Thread.new { job.handle.kill!(grace: KILL_GRACE) }
        end

        # @param key [String]
        # @param seconds [Integer]
        # @return [Boolean] whether a running agent's clock moved
        def extend(key, seconds)
          job = @desk.job(key) or return false
          return false unless job.handle&.extend!(seconds)

          @desk.feed.append(:extension, plan: @desk.plan_of(job), agent: job.task.agent.name, seconds:)
          true
        end

        # A person's answer to an `X<n>` request (E1). A time choice reaches
        # the agent's clock while that agent still runs on the plan; otherwise
        # the answer is one more round.
        #
        # @return [Hash, nil] the request as settled, nil when it already was
        def answer_extension(subject, number, letter, by:)
          request = Plans::PlanState.for(subject.feature.path).extensions.find { it["number"] == number }
          live = request && @desk.job("#{subject.feature.ordinal}/#{request["agent"]}")&.handle
          @desk.extensions.answer!(subject.feature.path, number, letter, by:, live:).tap { @desk.wake! }
        end

        # Stop the agent with a resume note (INTERRUPT is the word that makes
        # it leave one) and give it its round back, so it starts again on
        # whatever model is now preferred.
        #
        # @param key [String]
        # @return [Boolean] whether there was a running agent to restart
        def requeue(key)
          @desk.signal(key, Execution::Control::INTERRUPT) or return false
          requeues = @desk.requeues
          requeues << key unless requeues.include?(key)
          true
        end

        # Compact one running agent's session and carry it on (W28).
        #
        # @return [OpenLanes::Execution::Executor::Compaction, nil] nil when
        #   nothing by that key is running
        def compact(key, model: nil) = @desk.job(key)&.handle&.compact!(model:)

        # The model one agent gets on one plan from its next invocation (W24).
        #
        # @param model [String, nil] nil forgets the choice
        # @return [Boolean] whether the executor can honour it
        def prefer_model(ordinal, agent, model)
          executor = @desk.runner.executor
          return false unless executor.respond_to?(:prefer_model)

          executor.prefer_model(ordinal, agent, model)
          @desk.models.delete([ordinal.to_s, agent.to_s])
          true
        end

        # The copilot's `/concurrency N`. Never signals a running agent.
        #
        # @raise [OpenLanes::Error] as {Runner#jobs=} does
        def concurrency=(count)
          @desk.runner.jobs = count
        end
      end
    end
  end
end
