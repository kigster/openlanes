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
    let(:signed_in) { OpenLanes::Adapters::Availability.up("codex", [], Time.now) }
    let(:signed_out) { OpenLanes::Adapters::Availability.down("claude", "no", Time.now) }

    before do
      allow(OpenLanes::Adapters.for("claude")).to receive(:probe).and_return(signed_out)
      allow(OpenLanes::Adapters).to receive(:for).and_wrap_original do |original, name|
        original.call(name).tap { |adapter| allow(adapter).to receive(:probe).and_return(name == "codex" ? signed_in : signed_out) }
      end
    end

    it "takes the first one signed in" do
      expect([route.label, route.adapter.call]).to match([include("codex"), be_a(OpenLanes::Setup::Extraction::CliAdapter)])
    end
  end

  describe "its CLI commands" do
    it "never let a CLI change anything" do
      lines = described_class::CLIS.values.map { it.call("say hi") }
      expect(lines).to contain_exactly(
        include("--tools", ""), include("--sandbox", "read-only"), include("--permission-mode", "plan"), include("--approval-mode", "plan")
      )
    end
  end
end
