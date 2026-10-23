# frozen_string_literal: true

require "inquirex-llm"

RSpec.describe OpenLanes::Setup::Extractor do
  let(:answer) { {} }
  let(:adapter) { instance_double(Inquirex::LLM::AnthropicAdapter) }
  let(:extractor) { described_class.new(adapter:) }

  before { allow(adapter).to receive(:call).and_return(answer) }

  describe ".from_env" do
    it "prefers the Anthropic key" do
      extractor = described_class.from_env("ANTHROPIC_API_KEY" => "a", "OPENAI_API_KEY" => "o")
      expect(extractor.provider).to eq(:anthropic)
    end

    it "takes the OpenAI key alone" do
      expect(described_class.from_env("OPENAI_API_KEY" => "o").provider).to eq(:openai)
    end

    it "is nil with neither key, or blank ones" do
      expect([described_class.from_env({}), described_class.from_env("ANTHROPIC_API_KEY" => " ")]).to eq([nil, nil])
    end

    it "reads the model from OPENLANES_EXTRACTION_MODEL" do
      extractor = described_class.from_env("ANTHROPIC_API_KEY" => "a", "OPENLANES_EXTRACTION_MODEL" => "claude-x")
      expect(extractor.instance_variable_get(:@model)).to eq("claude-x")
    end

    it "builds the adapter for its key on first use" do
      extractor = described_class.from_env("OPENAI_API_KEY" => "o")
      expect(extractor.send(:adapter)).to be_a(Inquirex::LLM::OpenAIAdapter)
    end
  end

  describe "#call" do
    let(:answer) do
      { merge_by: "Auto", desired_codebase_quality: "ultra", language: "ruby", frameworks: ["rails", "", 3],
        persistence: "  ", caching: nil, domain: "payroll" }
    end

    it "keeps only the answered fields, inside their vocabularies" do
      expect(extractor.call("A payroll app in Rails")).to eq(
        merge_by: :auto, language: "ruby", frameworks: ["rails"], domain: "payroll"
      )
    end

    it "hands the adapter the description" do
      extractor.call("A payroll app")
      expect(adapter).to have_received(:call).with(an_object_having_attributes(id: :stack),
        { description: "A payroll app" })
    end

    it "asks nothing for a blank description" do
      expect(extractor.call(" ")).to eq({})
      expect(adapter).not_to have_received(:call)
    end

    it "answers nothing when the adapter fails" do
      allow(adapter).to receive(:call).and_raise(StandardError, "timeout")
      expect(extractor.call("A payroll app")).to eq({})
    end

    it "drops an empty framework list" do
      allow(adapter).to receive(:call).and_return(frameworks: [], language: :go)
      expect(extractor.call("Go")).to eq(language: "go")
    end
  end
end
