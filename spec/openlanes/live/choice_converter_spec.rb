# frozen_string_literal: true

require "inquirex-llm"

# No request leaves the machine: every example hands the converter an
# adapter double in place of Inquirex::LLM::OpenRouterAdapter.
RSpec.describe OpenLanes::Live::ChoiceConverter do
  subject(:converter) { described_class.new(adapter:, model: "test/model") }

  let(:calls) { [] }
  let(:output) do
    { context: "Seven units will not fit one 1200-second round.",
      options: [{ label: "Split the plan in two", recommended: true }, { label: "Raise the budget", recommended: false }] }
  end
  let(:adapter) do
    double = Object.new
    asked = calls
    answer = -> { output }
    double.define_singleton_method(:call) do |node, answers|
      asked << [node, answers]
      answer.call
    end
    double
  end

  def convert = converter.call(heading: "B1 Budget", body: "Seven units... A 1200-second budget is unlikely to cover them.")

  it "asks for context and options, as an extract over the heading and the question" do
    convert
    node, answers = calls.first
    aggregate_failures do
      expect(answers).to eq(heading: "B1 Budget", question: "Seven units... A 1200-second budget is unlikely to cover them.")
      expect(node.schema.fields).to eq(context: :string, options: :array)
      expect(node.from_steps).to eq(%i[heading question])
    end
  end

  it "writes D3's shape, with the model that wrote it" do
    result = convert
    expect([result.body, result.count, result.model]).to eq(
      ["Seven units will not fit one 1200-second round.\n\na) Split the plan in two (Recommended)\nb) Raise the budget\n", 2, "test/model"]
    )
  end

  context "when the model writes the recommendation into a label and adds a free-text option" do
    let(:output) do
      { "context" => "Which?",
        "options" => [{ "label" => "Rebase (Recommended)", "recommended" => "true" }, { "label" => "Merge\nnow" },
                      { "label" => "Type something instead", "recommended" => false }] }
    end

    it "takes both out, since the flag and the page already say them" do
      expect(convert.body).to eq("Which?\n\na) Rebase (Recommended)\nb) Merge now\n")
    end
  end

  {
    "no context"                     => { context: " ", options: [] },
    "1 option, not 2 or more"        => { context: "Which?", options: [{ label: "One", recommended: true }] },
    "2 options recommended, not one" => { context: "Which?", options: [{ label: "A", recommended: true }, { label: "B", recommended: true }] },
    "0 options recommended, not one" => { context: "Which?", options: [{ label: "A" }, { label: "B" }] },
    "an option is not an object"     => { context: "Which?", options: %w[A B] },
    "an option has no label"         => { context: "Which?", options: [{ label: "" }, { label: "B", recommended: true }] },
    "the context holds a heading"    => { context: "Which?\n## B2 More", options: [{ label: "A", recommended: true }, { label: "B" }] }
  }.each do |why, answer|
    context "when the answer has #{why}" do
      let(:output) { answer }

      it { expect { convert }.to raise_error(described_class::Invalid, why) }
    end
  end

  context "when the rewrite would not read back" do
    let(:output) { { context: "Which?", options: [{ label: "A\n\nB", recommended: true }, { label: "C" }] } }

    before { allow(OpenLanes::Plans::Choices).to receive(:parse).and_return(nil) }

    it { expect { convert }.to raise_error(described_class::Invalid, /does not read back/) }
  end

  describe ".from_env" do
    let(:config) { OpenLanes::Config.new }

    it "is nil without a key, so nothing is ever sent" do
      expect(described_class.from_env({ "OPENROUTER_API_KEY" => " " }, config:)).to be_nil
    end

    it "takes the default model" do
      expect(described_class.from_env({ "OPENROUTER_API_KEY" => "k" }, config:).model).to eq(described_class::DEFAULT_MODEL)
    end

    it "takes questions.model from .openlanes.yml" do
      converter = described_class.from_env({ "OPENROUTER_API_KEY" => "k" }, config: OpenLanes::Config.new(questions_model: "x/y"))
      expect(converter.model).to eq("x/y")
    end
  end

  it "builds the OpenRouter adapter when none is given" do
    adapter = described_class.new(api_key: "k", model: "x/y").send(:adapter)
    expect([adapter.class, adapter.instance_variable_get(:@default_model)]).to eq([Inquirex::LLM::OpenRouterAdapter, "x/y"])
  end
end
