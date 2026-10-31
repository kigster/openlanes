# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::Extraction::Routes do
  subject(:route) { described_class.new(env:, ollama:, runner:, cli_runner: runner).first }

  let(:env) { {} }
  let(:ollama) { instance_double(OpenLanes::Setup::Extraction::Ollama, models: [], chat_url: "http://127.0.0.1:11434/v1/chat/completions") }
  let(:runner) { instance_double(OpenLanes::Adapters::ProbeRunner, which: nil) }

  def adapter_ivar(name) = route.adapter.call.instance_variable_get(name)

  context "with nothing" do
    it { is_expected.to be_nil }
  end

  {
    "ANTHROPIC_API_KEY"  => [/Anthropic/, "Inquirex::LLM::AnthropicAdapter"],
    "OPENAI_API_KEY"     => [/OpenAI/, "Inquirex::LLM::OpenAIAdapter"],
    "XAI_API_KEY"        => [/Grok/, "OpenLanes::Setup::Extraction::XaiAdapter"],
    "GEMINI_API_KEY"     => [/Gemini/, "OpenLanes::Setup::Extraction::GeminiAdapter"],
    "OPENROUTER_API_KEY" => [/OpenRouter/, "Inquirex::LLM::OpenRouterAdapter"]
  }.each do |variable, (label, adapter)|
    context "with #{variable}" do
      let(:env) { { variable => " not-a-real-key " } }

      it "names it, and builds its adapter on the trimmed key" do
        expect([route.label, route.adapter.call.class.name, adapter_ivar(:@api_key)]).to match([label, adapter, "not-a-real-key"])
      end
    end
  end

  context "with several keys" do
    let(:env) { { "OPENROUTER_API_KEY" => "b", "ANTHROPIC_API_KEY" => "a" } }

    its(:label) { is_expected.to include("Anthropic") }
  end

  context "with a blank key, and a model named" do
    let(:env) { { "ANTHROPIC_API_KEY" => "  ", "XAI_API_KEY" => "x", "OPENLANES_EXTRACTION_MODEL" => "grok-small" } }

    it "skips the blank one and uses the model" do
      expect([route.label, adapter_ivar(:@default_model)]).to match([include("Grok"), "grok-small"])
    end
  end

  context "with a local Ollama" do
    before { allow(ollama).to receive(:models).and_return(%w[llama4 qwen3]) }

    it "takes the first model it has pulled" do
      expect([route.label, route.adapter.call]).to match([include("Ollama", "llama4"), be_a(OpenLanes::Setup::Extraction::OllamaAdapter)])
    end

    context "with a key too" do
      let(:env) { { "OPENAI_API_KEY" => "k" } }

      its(:label) { is_expected.to include("OpenAI") }
    end
  end

  context "with a signed-in CLI" do
    let(:env) { { "ANTHROPIC_API_KEY" => "not-a-real-key", "OPENLANES_EXTRACTION_MODEL" => "a-model" } }

    before do
      allow(OpenLanes::Adapters).to receive(:availability).and_return(
        [OpenLanes::Adapters::Availability.down("claude", "no", Time.now), OpenLanes::Adapters::Availability.up("pi", [], Time.now)]
      )
      allow(runner).to receive(:call).and_return(OpenLanes::Adapters::ProbeRunner::Result.new(stdout: "{}", stderr: "", status: 0))
    end

    it "takes the first one signed in, ahead of a key" do
      expect([route.label, route.adapter.call]).to match([include("pi"), be_a(OpenLanes::Setup::Extraction::CliAdapter)])
    end

    it "asks through the adapter's read-only command" do
      route.adapter.call.send(:call_api, system: "read", user: "a shop")
      expect(runner).to have_received(:call).with("pi",
        "--print",
        "--no-session",
        "--no-tools",
        "--no-extensions",
        "--no-skills",
        "--no-prompt-templates",
        "--model",
        "a-model",
        "read\n\na shop")
    end
  end
end
