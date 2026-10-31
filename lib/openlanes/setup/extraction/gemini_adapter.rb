# frozen_string_literal: true

require "inquirex-llm"

module OpenLanes
  module Setup
    module Extraction
      # Google's Gemini models, through its OpenAI-compatible endpoint.
      class GeminiAdapter < Inquirex::LLM::OpenAIAdapter
        API_URL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"

        private

        # @return [String]
        def provider_name = "Gemini"
      end
    end
  end
end
