# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Budget do
  let(:event) do
    OpenLanes::Events::Event.new(event_id: "a",
      kind: "agent_finished",
      at: Time.now,
      plan: "001.00",
      payload: { "round" => 1, "cost_usd" => 3.0 })
  end
  let(:reads) { [] }
  let(:clock) { Struct.new(:now).new(Time.at(0)) }
  let(:budget) { described_class.new(cap: -> { cap }, events: -> { (reads << 1) && [event] }, clock:) }
  let(:cap) { 2.0 }

  it "refuses a plan at or past its cap" do
    expect(budget.refusal("001.00")).to eq("over budget: $3.00 of $2.00")
  end

  it "lets a plan under its cap run" do
    expect(budget.refusal("002.00")).to be_nil
  end

  context "with no cap" do
    let(:cap) { nil }

    it "reads no log and refuses nothing" do
      expect([budget.refusal("001.00"), reads]).to eq([nil, []])
    end
  end

  it "rereads the log only once its TTL passes" do
    2.times { budget.spend("001.00") }
    clock.now = Time.at(described_class::TTL)
    budget.spend("001.00")
    expect(reads.size).to eq(2)
  end

  it "reads nothing for a runner whose log is off" do
    runner = Struct.new(:events).new(OpenLanes::Events::NullSink.new)
    expect(described_class.for(runner).spend("001.00").usd).to eq(0.0)
  end

  it "reads a runner's sink directory" do
    Dir.mktmpdir do |dir|
      sink = OpenLanes::Events::Sink.new(dir:, node: "n", checkout: "c")
      expect(described_class.for(Struct.new(:events).new(sink)).spend("001.00").usd).to eq(0.0)
    end
  end
end
