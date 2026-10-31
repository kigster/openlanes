# frozen_string_literal: true

require "inquirex-llm"

module OpenLanes
  module Setup
    module Extraction
      # A local Ollama model. Its endpoint is OpenAI's shape, but plain HTTP
      # and slow, which the parent's TLS-only `call_api` cannot reach.
      class OllamaAdapter < Inquirex::LLM::OpenAIAdapter
        # Seconds a local model may take; it may have to load first.
        READ_TIMEOUT = 180

        # @param url [String] the chat completions endpoint
        # @param model [String]
        def initialize(url:, model:)
          super(api_key: "ollama", model:)
          @url = URI(url)
        end

        private

        # @return [String]
        def provider_name = "Ollama"

        # @return [Hash] the parsed response
        # @raise [Inquirex::LLM::Errors::AdapterError] on anything but a success
        def call_api(**)
          request = Net::HTTP::Post.new(@url, "Content-Type" => "application/json")
          request.body = JSON.generate(request_body(**))
          response = Net::HTTP.start(@url.host, @url.port, read_timeout: READ_TIMEOUT) { it.request(request) }
          raise Inquirex::LLM::Errors::AdapterError, "Ollama error #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        end
      end
    end
  end
end
