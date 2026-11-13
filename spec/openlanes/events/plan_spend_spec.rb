# frozen_string_literal: true

RSpec.describe OpenLanes::Events::PlanSpend do
  def finished(id, plan:, cost:, **run)
    OpenLanes::Events::Event.new(event_id: id,
      kind: "agent_finished",
      at: Time.iso8601("2026-11-12T12:00:00Z"),
      plan:,
      run: "r1",
      agent: run.fetch(:agent, "backend-coder"),
      payload: { "round" => run.fetch(:round, 1), "status" => "Completed", "cost_usd" => cost })
  end

  let(:events) do
    [finished("a", plan: "062.00", cost: 1.25),
     finished("b", plan: "062.00", cost: 2.5, agent: "frontend-coder"),
     finished("c", plan: "062.00", cost: 0.75, round: 2),
     finished("d", plan: "062.00", cost: nil, agent: "codex-reviewer"),
     finished("e", plan: "063.00", cost: 9.0),
     OpenLanes::Events::Event.new(event_id: "s",
       kind: "agent_started",
       at: Time.now,
       plan: "062.00",
       payload: { "round" => 3 })]
  end

  it "sums priced runs across agents and rounds for one plan, ignoring other plans" do
    expect(described_class.for("062.00", events).usd).to eq(4.5)
  end

  it "counts an unpriced run separately, never as $0" do
    expect(described_class.for("062.00", events)).to have_attributes(unpriced_runs: 1, usd: 4.5)
  end

  it "reads nothing as zero spend" do
    expect(described_class.for("064.00", events)).to have_attributes(usd: 0.0, unpriced_runs: 0, over?: false)
  end

  { 4.0 => true, 4.5 => true, 5.0 => false }.each do |cap, over|
    it "is #{"not " unless over}over a cap of $#{cap}" do
      expect(described_class.for("062.00", events, cap:).over?).to be(over)
    end
  end

  it "is never over with no cap" do
    expect(described_class.for("062.00", events)).to have_attributes(over?: false, share: nil, reason: nil)
  end

  it "says the share and the hold reason" do
    spend = described_class.for("062.00", events, cap: 4.0)
    expect([spend.share, spend.reason]).to eq([1.125, "over budget: $4.50 of $4.00"])
  end

  it "wires the snapshot's spend" do
    expect(described_class.for("062.00", events, cap: 5.0).wire)
      .to eq(usd: 4.5, cap: 5.0, over: false, unpriced_runs: 1)
  end
end
