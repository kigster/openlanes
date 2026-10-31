# frozen_string_literal: true

require "inquirex-llm"

module OpenLanes
  module Setup
    module Extraction
      # xAI's Grok models, through its OpenAI-compatible endpoint.
      class XaiAdapter < Inquirex::LLM::OpenAIAdapter
        API_URL = "https://api.x.ai/v1/chat/completions"

        private

        # @return [String]
        def provider_name = "xAI"
      end
    end
  end
end
