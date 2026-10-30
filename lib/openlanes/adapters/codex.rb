# frozen_string_literal: true

require "json"

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
        confines: false,
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

      # Codex's read-only sandbox, from any folder, without the operator's config.
      #
      # @param prompt [String]
      # @param model [String, nil]
      # @return [Array<String>]
      def question_argv(prompt, model: nil)
        ["codex", "exec", "--sandbox", "read-only", "--skip-git-repo-check", "--ignore-user-config",
         *(model ? ["--model", model] : []), prompt]
      end

      # @param effort [String, nil]
      # @return [String, nil]
      def effort(effort) = effort && EFFORT[effort.to_s]

      private

      # `codex login status` exits 1 signed out and 0 signed in. The models
      # come from the list bundled with the binary, read offline; one codex
      # marks `hide` is not offered.
      #
      # @param runner [OpenLanes::Adapters::ProbeRunner]
      # @param at [Time]
      # @return [OpenLanes::Adapters::Availability]
      def check(runner, at)
        login = runner.call("codex", "login", "status")
        return timed_out(login, at) if login.timed_out?
        return Availability.down(name, "not signed in (run `codex login`)", at) unless login.ok?

        models = listed(runner.call("codex", "debug", "models", "--bundled"))
        return Availability.down(name, "signed in, but `codex debug models --bundled` listed no models", at) if models.empty?

        Availability.up(name, models, at)
      end

      # @param result [OpenLanes::Adapters::ProbeRunner::Result]
      # @return [Array<OpenLanes::Adapters::Model>] empty when the list cannot be read
      def listed(result)
        return [] unless result.ok?

        JSON.parse(result.stdout).fetch("models", []).filter_map do |entry|
          next if entry["visibility"] == "hide" || entry["slug"].to_s.empty?

          Model.new(id: entry["slug"],
            label: entry["display_name"] || entry["slug"],
            context: entry["context_window"] || Model::WINDOW)
        end
      rescue JSON::ParserError, NoMethodError, TypeError
        []
      end
    end
  end
end
