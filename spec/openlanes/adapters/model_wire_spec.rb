# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Model do
  describe "a model nobody has priced" do
    subject(:model) { described_class.new(id: "gpt-5.5", label: "GPT-5.5") }

    it { is_expected.not_to be_priced }
    it { expect(model.cost(1_000_000, 1_000_000)).to eq(0.0) }
    it { expect(model.wire).to eq(id: "gpt-5.5", label: "GPT-5.5", rates: nil, context: 200_000) }
    it { expect(described_class.from_wire(JSON.parse(JSON.generate(model.wire)))).to eq(model) }
  end

  describe "a priced model" do
    subject(:model) { described_class.new(id: "claude-opus-5-5", label: "Opus 5.5", rate_in: 4, rate_out: 20) }

    it { is_expected.to be_priced }
    it { expect(model.cost(1_000_000, 1_000_000)).to eq(24.0) }
    it { expect(described_class.from_wire(JSON.parse(JSON.generate(model.wire)))).to eq(model) }
  end

  # Grok on #151: the window was left off the wire, so codex's 272k models
  # came back out of Redis at 200k.
  describe "a model with a window of its own" do
    subject(:model) { described_class.new(id: "gpt-6-sol", label: "GPT-6-Sol", context: 272_000) }

    it { expect(described_class.from_wire(JSON.parse(JSON.generate(model.wire))).context).to eq(272_000) }
  end

  describe "a wire written before the window rode along" do
    it { expect(described_class.from_wire("id" => "gpt-5.5", "label" => "GPT-5.5").context).to eq(described_class::WINDOW) }
  end
end
