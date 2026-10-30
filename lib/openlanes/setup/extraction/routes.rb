# frozen_string_literal: true

module OpenLanes
  module Setup
    module Extraction
      # Finds the first way to read a description, in this order: an API key the
      # person set, then their local Ollama, then an agent CLI they signed in to.
      # A key comes first because setting one is a deliberate choice; Ollama
      # before a CLI because the description then stays on the machine.
      class Routes
        # One API key: its variable, what it is called, the adapter, the model
        # used when OPENLANES_EXTRACTION_MODEL names none (nil: the adapter's own).
        Key = Data.define(:env, :label, :adapter, :model)

        # Every key read, in the order tried.
        KEYS = [
          Key.new("ANTHROPIC_API_KEY", "Anthropic", -> { Inquirex::LLM::AnthropicAdapter }, "claude-sonnet-5-5"),
          Key.new("OPENAI_API_KEY", "OpenAI", -> { Inquirex::LLM::OpenAIAdapter }, nil),
          Key.new("XAI_API_KEY", "xAI Grok", -> { XaiAdapter }, "grok-4.7"),
          Key.new("GEMINI_API_KEY", "Google Gemini", -> { GeminiAdapter }, "gemini-3.5-flash"),
          Key.new("OPENROUTER_API_KEY", "OpenRouter", -> { Inquirex::LLM::OpenRouterAdapter }, nil)
        ].freeze

        # Agent CLI → its one-shot command, in the mode that cannot change
        # anything: no tools, a read-only sandbox, or plan mode.
        CLIS = {
          "claude" => ->(prompt) { ["claude", "-p", prompt, "--output-format", "text", "--tools", ""] },
          "codex"  => ->(prompt) { ["codex", "exec", "--sandbox", "read-only", "--skip-git-repo-check", prompt] },
          "grok"   => ->(prompt) { ["grok", "-p", prompt, "--permission-mode", "plan"] },
          "gemini" => ->(prompt) { ["gemini", "-p", prompt, "--approval-mode", "plan", "--skip-trust", "-o", "text"] }
        }.freeze

        # Seconds a CLI may take over one description.
        CLI_TIMEOUT = 120

        # @param env [#[]]
        # @param ollama [#models] the local server
        # @param runner [OpenLanes::Adapters::ProbeRunner] asks whether a CLI is signed in
        # @param cli_runner [OpenLanes::Adapters::ProbeRunner] runs the extraction, with a longer timeout
        def initialize(env: ENV, ollama: Ollama.new(host: env["OLLAMA_HOST"]), runner: Adapters.probe_runner,
          cli_runner: Adapters::ProbeRunner.new(timeout: CLI_TIMEOUT))
          @env = env
          @ollama = ollama
          @runner = runner
          @cli_runner = cli_runner
        end

        # @return [OpenLanes::Setup::Extraction::Route, nil]
        def first = keyed || local || signed_in

        private

        # @return [String, nil]
        def model = @env["OPENLANES_EXTRACTION_MODEL"].to_s.strip.then { it.empty? ? nil : it }

        # @return [OpenLanes::Setup::Extraction::Route, nil]
        def keyed
          key = KEYS.find { !@env[it.env].to_s.strip.empty? } or return nil

          Route.new(label: "#{key.label} (#{key.env})",
            adapter: -> { key.adapter.call.new(api_key: @env[key.env].strip, model: model || key.model) })
        end

        # @return [OpenLanes::Setup::Extraction::Route, nil]
        def local
          chosen = model || @ollama.models.first or return nil

          Route.new(label: "Ollama on this machine (#{chosen})",
            adapter: -> { OllamaAdapter.new(url: @ollama.chat_url, model: chosen) })
        end

        # @return [OpenLanes::Setup::Extraction::Route, nil]
        def signed_in
          name = CLIS.keys.find { Adapters.for(it).probe(runner: @runner).available } or return nil

          Route.new(label: "the #{name} CLI you are signed in to",
            adapter: -> { CliAdapter.new(command: CLIS.fetch(name), runner: @cli_runner, label: name) })
        end
      end
    end
  end
end
