# frozen_string_literal: true

module OpenLanes
  module Setup
    module Extraction
      # Finds the first way to read a description, in this order: an agent CLI
      # {Adapters} can already reach, however it is signed in, then an API key,
      # then a local Ollama. The CLIs come first because the person already
      # trusts them with this code, while a key in the environment may be the
      # application's own (see {Execution::Executor::CREDENTIAL_VARS}). The
      # person is told which one before they type anything.
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
        def first = signed_in || keyed || local

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
          name = Adapters.availability(runner: @runner).find(&:available)&.name or return nil

          Route.new(label: "the #{name} CLI you are signed in to",
            adapter: -> { CliAdapter.new(command: question(name), runner: @cli_runner, label: name) })
        end

        # @param name [String] an adapter's name
        # @return [#call] takes the prompt, answers with argv
        def question(name) = ->(prompt) { Adapters.for(name).question_argv(prompt, model:) }
      end
    end
  end
end
