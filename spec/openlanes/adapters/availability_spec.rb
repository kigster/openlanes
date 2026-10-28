# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Availability do
  let(:at) { Time.utc(2026, 10, 27, 9) }
  let(:model) { OpenLanes::Adapters::Model.new(id: "gpt-5.5", label: "GPT-5.5") }

  describe ".up" do
    subject(:availability) { described_class.up("codex", [model], at) }

    it { is_expected.to be_available }
    it { expect(availability.reason).to be_nil }
  end

  describe ".down" do
    subject(:availability) { described_class.down("pi", "not signed in", at) }

    it { is_expected.not_to be_available }
    it { expect([availability.reason, availability.models]).to eq(["not signed in", []]) }
  end

  describe ".unchecked" do
    subject(:availability) { described_class.unchecked(OpenLanes::Adapters.for("claude")) }

    it { expect([availability.available, availability.checked_at]).to eq([nil, nil]) }
    it { expect(availability.models).to eq(OpenLanes::Adapters::Claude::MODELS) }
    it { is_expected.not_to be_available }
  end

  describe "#wire and .from_wire" do
    subject(:wire) { described_class.up("codex", [model], at).wire }

    it { is_expected.to eq(name: "codex", available: true, reason: nil, checked_at: "2026-10-27T09:00:00Z", models: [{ id: "gpt-5.5", label: "GPT-5.5", rates: nil }]) }

    it "round-trips through JSON" do
      expect(described_class.from_wire(JSON.parse(JSON.generate(wire)))).to eq(described_class.up("codex", [model], at))
    end

    it "reads an unchecked one back with no time" do
      expect(described_class.from_wire("name" => "pi", "available" => nil).checked_at).to be_nil
    end
  end
end
