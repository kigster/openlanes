# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Model do
  describe "a model nobody has priced" do
    subject(:model) { described_class.new(id: "gpt-5.5", label: "GPT-5.5") }

    it { is_expected.not_to be_priced }
    it { expect(model.cost(1_000_000, 1_000_000)).to eq(0.0) }
    it { expect(model.wire).to eq(id: "gpt-5.5", label: "GPT-5.5", rates: nil) }
    it { expect(described_class.from_wire(JSON.parse(JSON.generate(model.wire)))).to eq(model) }
  end

  describe "a priced model" do
    subject(:model) { described_class.new(id: "claude-opus-5-5", label: "Opus 5.5", rate_in: 4, rate_out: 20) }

    it { is_expected.to be_priced }
    it { expect(model.cost(1_000_000, 1_000_000)).to eq(24.0) }
    it { expect(described_class.from_wire(JSON.parse(JSON.generate(model.wire)))).to eq(model) }
  end
end
