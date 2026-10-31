# frozen_string_literal: true

RSpec.describe "the hosted adapters inquirex-llm lacks" do
  {
    OpenLanes::Setup::Extraction::XaiAdapter    => ["https://api.x.ai/", "xAI"],
    OpenLanes::Setup::Extraction::GeminiAdapter => ["https://generativelanguage.googleapis.com/", "Gemini"]
  }.each do |adapter, (url, name)|
    it "points #{name} at its own endpoint" do
      built = adapter.new(api_key: "not-a-real-key", model: "a-model")
      expect([built.send(:api_url), built.send(:provider_name)]).to match([start_with(url), name])
    end
  end
end
