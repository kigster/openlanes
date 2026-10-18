# frozen_string_literal: true

require "inquirex-llm"

# No request leaves the machine: every example hands the interviewer an
# adapter double in place of Inquirex::LLM::OpenRouterAdapter.
RSpec.describe OpenLanes::Live::Interviewer do
  subject(:interviewer) { described_class.new(adapter:, model: "test/model") }

  let(:calls) { [] }
  let(:good) do
    { "context" => "Who opens the export?", "options" => [{ "label" => "The accountant", "recommended" => true },
                                                          { "label" => "Anyone on the team", "recommended" => false }] }
  end
  let(:output) { { questions: [good] } }
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

  def interview = interviewer.call(idea: "Export the ledger as CSV")

  # Grok on #81: a slow model must not hold the dialog and a Puma thread for
  # the HTTP client's full 40 seconds.
  it "gives up on a model slower than its timeout" do
    slow = Object.new
    slow.define_singleton_method(:call) { |*| sleep 1 }
    patient = described_class.new(adapter: slow, timeout: 0.05)

    expect { patient.call(idea: "x") }.to raise_error(Timeout::Error, "no questions within 0.05s")
  end

  it "asks for questions, as an extract over the idea" do
    interview
    node, answers = calls.first
    aggregate_failures do
      expect(answers).to eq(idea: "Export the ledger as CSV")
      expect(node.schema.fields).to eq(questions: :array)
      expect(node.from_steps).to eq(%i[idea])
    end
  end

  it "returns each question with its options and the one recommended" do
    expect(interview.map(&:wire)).to eq(
      [{ context: "Who opens the export?", options: ["The accountant", "Anyone on the team"], recommended: 0 }]
    )
  end

  context "when some questions are not D3" do
    let(:output) do
      { questions: ["not an object", { "context" => "Which?", "options" => [{ "label" => "Only", "recommended" => true }] },
                    good] }
    end

    it "drops them and keeps the rest" do
      expect(interview.map(&:context)).to eq(["Who opens the export?"])
    end
  end

  context "when the model asks too much" do
    let(:output) { { questions: Array.new(8) { good } } }

    it "keeps the first #{described_class::LIMIT}" do
      expect(interview.size).to eq(described_class::LIMIT)
    end
  end

  context "when the model leaves nothing open" do
    let(:output) { {} }

    it "returns no questions" do
      expect(interview).to eq([])
    end
  end

  describe ".from_env" do
    it "is nil without a key" do
      expect(described_class.from_env({})).to be_nil
    end

    it "is an interviewer with one" do
      expect(described_class.from_env({ "OPENROUTER_API_KEY" => "sk-x" })).to be_a(described_class)
    end
  end

  describe "the default adapter" do
    subject(:interviewer) { described_class.new(api_key: "sk-x") }

    it "is OpenRouter's, built on first use" do
      expect(interviewer.send(:adapter)).to be_a(Inquirex::LLM::OpenRouterAdapter)
    end
  end
end
