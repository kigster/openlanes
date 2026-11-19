# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # The collaborators one executor runs every invocation through, wired
      # once from its {Options}.
      #
      # @!attribute [r] launcher
      #   @return [OpenLanes::Execution::Executor::Launcher]
      # @!attribute [r] invocations
      #   @return [OpenLanes::Execution::Executor::Invocation]
      # @!attribute [r] supervision
      #   @return [OpenLanes::Execution::Executor::Supervision]
      # @!attribute [r] verdict
      #   @return [OpenLanes::Execution::Executor::Verdict]
      # @!attribute [r] preferences
      #   @return [OpenLanes::Execution::Executor::Preferences]
      # @!attribute [r] trace_dir
      #   @return [String]
      Crew = Data.define(:launcher, :invocations, :supervision, :verdict, :preferences, :trace_dir) do
        # @param options [OpenLanes::Execution::Executor::Options]
        # @param preferences [OpenLanes::Execution::Executor::Preferences]
        # @param invocations [OpenLanes::Execution::Executor::Invocation]
        # @return [OpenLanes::Execution::Executor::Crew]
        def self.build(options, preferences, invocations)
          launcher = Launcher.new(spawn: options.spawn || AgentProcess.spawner(dir: options.trace_dir, root: options.root))
          new(launcher:,
            invocations:,
            preferences:,
            trace_dir: options.trace_dir,
            supervision: supervision(options, launcher, invocations),
            verdict: Verdict.new(max_tokens: options.max_tokens))
        end

        # @return [OpenLanes::Execution::Executor::Supervision]
        def self.supervision(options, launcher, invocations)
          drain = Drain.new(max_tokens: options.max_tokens, fresh_budget: options.fresh_budget)
          Supervision.new(drain:,
            throttling: ThrottleWait.new(throttle: options.throttle, launcher:, invocations:, drain:),
            compactor:  Compactor.new(launcher:, invocations:, drain:))
        end
      end
    end
  end
end
