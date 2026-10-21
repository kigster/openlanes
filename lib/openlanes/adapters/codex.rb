# frozen_string_literal: true

module OpenLanes
  module Adapters
    # `codex exec --json`, inside codex's own workspace-write sandbox.
    #
    # The sandbox has no network unless the agent declares `network: true`,
    # which is the same default the Claude adapter gets from withholding
    # WebFetch and WebSearch. Codex has no per-command denylist, so the
    # forbidden commands are stated in the prompt and the after-check (HEAD
    # unmoved, no new remote ref) is what actually holds the line.
    class Codex < Base
      # Codex says `xhigh` for the top of its scale and has no `max`.
      EFFORT = { "low" => "low", "medium" => "medium", "high" => "high", "xhigh" => "xhigh", "max" => "xhigh" }.freeze

      # No session to resume, so nothing to compact, and no denylist of its own.
      CAPABILITIES = Capabilities.new(compacts: false,
        resumes: false,
        enforces_tool_denial: false,
        compact_prompt: nil)

      # @return [OpenLanes::Adapters::Capabilities]
      def capabilities = CAPABILITIES

      # @param invocation [OpenLanes::Adapters::Invocation]
      # @return [Array<String>]
      def argv(invocation)
        argv = ["codex", "exec", "--json", "--sandbox", "workspace-write", "--cd", invocation.root]
        argv << "--ignore-user-config" if invocation.lean
        argv += ["--model", invocation.model] if invocation.model
        effort = effort(invocation.effort)
        argv += ["--config", %(model_reasoning_effort="#{effort}")] if effort
        argv += ["--config", "sandbox_workspace_write.network_access=true"] if invocation.network
        argv << invocation.prompt
      end

      # @param effort [String, nil]
      # @return [String, nil]
      def effort(effort) = effort && EFFORT[effort.to_s]
    end
  end
end
