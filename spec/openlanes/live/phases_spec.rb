# frozen_string_literal: true

RSpec.describe OpenLanes::Live::Phases do
  subject(:wire) { described_class.wire(OpenLanes::Agents.registry) }

  let(:names) { ->(starts) { wire.fetch(starts).map { it[:phase] } } }

  it "walks every phase from research" do
    expect(names.call("research")).to eq(%w[research specification planning build frontend review verification completion])
  end

  it "skips research and the spec when a plan starts at planning" do
    expect(names.call("planning")).to eq(%w[planning build frontend review verification completion])
  end

  it "has one builder, and no front end, when a plan starts at building" do
    expect(names.call("building")).to eq(%w[build review verification completion])
  end

  it "names the key that switches the front end off" do
    expect(wire["research"].find { it[:phase] == "frontend" }).to eq(phase: "frontend", toggle: "frontend")
  end

  describe ".entry" do
    it { expect(described_class.entry(:research)).to eq(:new) }
    it { expect(described_class.entry(:planning)).to eq(:ready_for_planning) }
    it { expect(described_class.entry(:building)).to eq(:planned) }
  end
end
