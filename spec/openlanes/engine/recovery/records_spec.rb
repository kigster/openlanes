# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Recovery::Records, :tree do
  subject(:records) { described_class.new(dry_run: false) }

  let(:agent) { instance_double(OpenLanes::Agents::Agent, name: "luke-backend", ledger: %w[plan.md]) }
  let(:plan) { OpenLanes::Plans::Tree.new(dir: plans_root).find("003.00") }
  let(:round) { OpenLanes::Engine::Recovery::Round.new(subject: plan, agent:, round: 2) }
  let(:state) { OpenLanes::Plans::PlanState.for(plan.feature.path) }

  before do
    plans { |t| t.plan "003.00", :building, "work" }
    allow(OpenLanes::UI).to receive(:log)
  end

  it "writes a stage for the round" do
    records.stage!(round, status: "Started")

    expect(state.stages.map { it.values_at("agent", "round", "status") }).to eq([["luke-backend", 2, "Started"]])
  end

  it "signs the round Interrupted, and that becomes the agent's last line" do
    records.interrupted(round, "harness died")

    expect(records.last_line(round).then { [it.status, it.round] }).to eq(["Interrupted", 2])
  end

  it "leaves a resume record naming the reason, the last line seen and the last phrase" do
    records.interrupted(round, "first")
    records.resume(round, "timed out", phrase: "running the suite")

    expect(state.last_known("luke-backend").note).to eq("timed out; last ledger line: Interrupted, round 2: first; last seen: running the suite")
  end

  it "writes nothing under a dry run" do
    dry = described_class.new(dry_run: true)
    dry.stage!(round, status: "Started")
    dry.resume(round, "timed out", last: nil)

    expect([state.stages, state.last_known("luke-backend")]).to eq([[], nil])
  end

  it "reports a state.json it cannot write and carries on" do
    allow(OpenLanes::Plans::PlanState).to receive(:for).and_raise(Errno::EACCES)
    records.stage!(round, status: "Started")
    records.resume(round, "timed out", last: nil)

    aggregate_failures do
      expect(OpenLanes::UI).to have_received(:log).with(/state.json not written/, level: :warn, plan: "003.00")
      expect(OpenLanes::UI).to have_received(:log).with(/resume record not written/, level: :warn, plan: "003.00")
    end
  end
end
