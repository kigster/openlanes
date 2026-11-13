# frozen_string_literal: true

require "json"

module OpenLanes
  module Adapters
    # `claude -p`, streaming JSON.
    class Claude < Base
      # The tier `claude` runs when an agent names no model, so an unnamed
      # model is still priced rather than shown as free.
      UNNAMED = "sonnet"

      # The models, their labels, rates and windows, live in {Catalogue}:
      # Anthropic's list when a credential lets this machine read it, the
      # shipped list otherwise. There is no ceiling. The one that capped
      # every agent at Opus kept Fable off the page and quietly ran a
      # `model: fable` agent on Opus; what an agent runs on is the
      # operator's call, priced on the page, not the adapter's.

      # The variable `claude` reads its autocompact threshold from, as a
      # percentage. Found in the 2.1.x binary, where `Vle()` reads it with
      # `parseFloat(process.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE)`.
      AUTOCOMPACT_VARIABLE = "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"

      # Flags that keep the operator's personal setup out of the agent. The
      # project's CLAUDE.md and settings still load. Measured on a one-word
      # prompt: 143 tools, 60 MCP servers, 358 skills and 17 hook events
      # without these; 28 tools and none of the rest with them, at three
      # quarters of the context and half the start-up time.
      LEAN = ["--setting-sources", "project,local",
              "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
              "--disable-slash-commands"].freeze

      # The one flag of {LEAN} a compaction drops: with it, `claude -p
      # --resume <id> "/compact"` answers "/compact isn't available in this
      # environment" and compacts nothing (measured on 2.1.x).
      SLASH_COMMANDS_OFF = "--disable-slash-commands"

      # @param invocation [OpenLanes::Adapters::Invocation]
      # @return [Array<String>]
      def argv(invocation)
        # `--include-partial-messages` is what the token meter runs on. Without
        # it the stream reports a settled input count and a placeholder output
        # count — 2 for a four-thousand-token answer — and a spinner counting
        # what came back would read zero all run.
        argv = ["claude", "-p", invocation.prompt, "--add-dir", invocation.root]
        invocation.dirs.each { argv += ["--add-dir", it] }
        argv += ["--output-format", "stream-json", "--verbose", "--include-partial-messages"]
        argv << "--brief" if invocation.brief
        argv += ["--resume", invocation.resume] if invocation.resume
        argv += LEAN.reject { invocation.slash_commands && it == SLASH_COMMANDS_OFF } if invocation.lean
        argv += restricted(invocation.tools) if invocation.tools
        argv += ["--append-system-prompt", invocation.system] if invocation.system
        argv += ["--disallowedTools", invocation.denied_tools.join(",")] unless invocation.denied_tools.empty?
        argv += ["--allowedTools", invocation.allowed_tools.join(",")] unless invocation.allowed_tools.empty?
        model = model(invocation.model)
        argv += ["--model", model] if model
        argv += ["--effort", invocation.effort] if invocation.effort
        argv
      end

      # No tools at all, and none of the operator's plugins, hooks or MCP servers.
      #
      # @param prompt [String]
      # @param model [String, nil]
      # @return [Array<String>]
      def question_argv(prompt, model: nil)
        chosen = model(model)
        ["claude", "-p", prompt, "--output-format", "text", *LEAN, *restricted([]), *(chosen ? ["--model", chosen] : [])]
      end

      # @return [OpenLanes::Execution::Transcript]
      def transcript(trace: nil, **, &) = Execution::Transcript.new(trace:, &)

      # A fixed tool set. `--tools` takes every other built-in tool away, and
      # `--restricted` stops the project's and the operator's settings files
      # from granting more: an allow rule in `.claude/settings.json` would
      # otherwise widen what `--allowedTools` permits, and `--disallowedTools`
      # only removes what somebody thought to name. `dontAsk` refuses whatever
      # the allow list does not cover, rather than waiting on a prompt that
      # nobody under `-p` can answer.
      #
      # @param tools [Array<String>]
      # @return [Array<String>]
      def restricted(tools) = ["--restricted", "--tools", tools.join(","), "--permission-mode", "dontAsk"]

      # An alias (`sonnet`) or a full id (`claude-fable-5-1`), asked for as
      # written: `claude` resolves its own aliases, and nothing here caps it.
      #
      # @param model [String, nil]
      # @return [String, nil]
      def model(model) = model.nil? || model.to_s.empty? ? model : model.to_s

      # `--disallowedTools` is refused by the CLI itself, and `--resume
      # <session id>` carries a conversation on. `claude -p --resume <id>
      # "/compact"` compacts the session and prints a `compact_boundary`
      # event; the agent cannot run it on itself, because `/compact` is the
      # caller's command, not a tool.
      CAPABILITIES = Capabilities.new(compacts: true,
        resumes: true,
        enforces_tool_denial: true,
        confines: true,
        compact_prompt: "/compact")

      # @return [OpenLanes::Adapters::Capabilities]
      def capabilities = CAPABILITIES

      # @return [Array<String>]
      def lean_flags = LEAN

      # @return [Hash{String => String}]
      def environment = { AUTOCOMPACT_VARIABLE => AUTOCOMPACT.to_s }

      # Every model Anthropic serves, most capable first; see {Catalogue}.
      #
      # @return [Array<OpenLanes::Adapters::Model>]
      def models = catalogue.models

      # A full id as itself, an alias that is exactly a tier (`opus`) as the
      # newest model of that tier, no name as {UNNAMED}; see {Catalogue#find}.
      #
      # @param name [String, nil]
      # @return [OpenLanes::Adapters::Model, nil]
      def model_entry(name) = catalogue.find(name)

      # @return [OpenLanes::Adapters::Claude::Catalogue]
      def catalogue = Catalogue.current

      private

      # `claude auth status --json`, of which only `loggedIn` is read: the
      # rest names the account, which has no business in a probe result.
      #
      # @param runner [OpenLanes::Adapters::ProbeRunner]
      # @param at [Time]
      # @return [OpenLanes::Adapters::Availability]
      def check(runner, at)
        result = runner.call("claude", "auth", "status", "--json")
        return timed_out(result, at) if result.timed_out?
        return Availability.up(name, models, at) if signed_in?(result.stdout)

        Availability.down(name, "not signed in (run `claude auth login`)", at)
      end

      # @param json [String]
      # @return [Boolean]
      def signed_in?(json)
        JSON.parse(json)["loggedIn"] == true
      rescue JSON::ParserError, NoMethodError
        false
      end
    end
  end
end
