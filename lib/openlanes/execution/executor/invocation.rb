# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module Execution
    class Executor
      # The argv one session is started with, and the trace it writes. Every
      # start, whether the first, a carried-on session or a `/compact`, gets
      # the same boundary flags, confined as the first one was.
      class Invocation
        # @param lean [Boolean] start agents without the operator's own plugins
        # @param trace_dir [String] where each invocation's raw stream is kept
        # @param prompts [OpenLanes::Execution::Executor::PromptAssembly, nil] the
        #   first start's prompt; nil for a builder that only carries sessions on
        def initialize(lean:, trace_dir:, prompts: nil)
          @lean = lean
          @trace_dir = trace_dir
          @prompts = prompts
        end

        # The argv a round starts with, its prompt assembled for the request.
        #
        # @param attempt [OpenLanes::Execution::Executor::Attempt]
        # @param request [OpenLanes::Execution::Executor::Request]
        # @return [Array<String>]
        def first(attempt, request) = argv(attempt, prompt: @prompts.prompt_for(attempt, request), resume: request.resume)

        # @param attempt [OpenLanes::Execution::Executor::Attempt] the agent,
        #   plan, checkout and profile; the profile's model is the one started
        # @param prompt [String]
        # @param resume [String, nil] a session id to carry on
        # @param slash_commands [Boolean] whether the prompt may be one
        # @return [Array<String>]
        def argv(attempt, prompt:, resume: nil, slash_commands: false)
          profile = attempt.profile
          flags = { prompt:, resume:, slash_commands:, root: attempt.root, lean: @lean }
          profile.adapter.argv(Adapters::Invocation.new(**flags, **chosen(profile), **boundary(attempt.agent, attempt.subject)))
        end

        # One file per invocation. The plan number and the agent's name make it
        # findable; the pid and the clock keep two concurrent runs from writing to
        # the same one. See {TRACE_DIR} for how to read one back.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject]
        # @return [String]
        def trace_path(agent, subject)
          FileUtils.mkdir_p(@trace_dir)
          stamp = Time.now.strftime("%Y%m%d-%H%M%S")
          File.join(@trace_dir, format("%s-%s-%s-%d-%04x.ndjson", stamp, subject.feature.ordinal, agent.name, Process.pid, rand(0x10000)))
        end

        private

        # @return [Hash{Symbol => Object}] the model and effort it runs on
        def chosen(profile) = { model: profile.model, effort: profile.effort }

        # @return [Hash{Symbol => Object}] what the agent may and may not use
        def boundary(agent, subject)
          { allowed_tools:   Confinement.allowed_for(agent, subject),
            denied_tools:    Grants.denied_for(agent),
            denied_commands: Grants.denied_commands(agent),
            network:         agent.network,
            tools:           (Confinement::CONFINED_TOOLS if agent.confined?) }
        end
      end
    end
  end
end
