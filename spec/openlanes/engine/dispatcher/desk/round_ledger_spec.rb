# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Dispatcher::Desk::RoundLedger, :tree do
  subject(:ledger) { described_class.new(registers:, runner:) }

  let(:registers) { OpenLanes::Engine::Dispatcher::Desk::Registers.fresh }
  let(:runner) { instance_double(OpenLanes::Engine::Runner, dry_run?: false) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:plan) { tree.reload.find("001.00") }
  let(:plan_state) { OpenLanes::Plans::PlanState.for(plan.feature.path) }
  let(:agent) { instance_double(OpenLanes::Agents::Agent, name: "researcher") }
  let(:seeded) { ledger.past_rounds(plan, agent).map { it.values_at(:round, :status) } }

  def stage(round, status, **)
    plan_state.stage!(agent: "researcher", round:, reset: true, status:, from: "new", state: "new", **)
  end

  before { plans { |t| t.plan "001.00", :new, "carry-on", files: { "spec.md" => spec_body } } }

  # A round handed back and started again runs twice under one number. The
  # first stage of it once won, so a round that had since Completed was
  # seeded as Interrupted and its agent was started on it once more.
  context "with a round run twice under one number" do
    before do
      stage(1, "Interrupted")
      stage(1, "Completed")
    end

    it "seeds the round as its latest stage has it" do
      expect(seeded).to eq([[1, "Completed"]])
    end

    it "hands out the round after it" do
      expect(ledger.next_round(plan, agent)).to eq(2)
    end
  end

  context "with a round the harness handed back" do
    before { stage(1, "Interrupted", handed_back: true) }

    it "seeds nothing spent, and hands the same number out again" do
      expect([seeded, ledger.next_round(plan, agent)]).to eq([[], 1])
    end
  end

  it "seeds nothing on a dry run" do
    stage(1, "Interrupted")
    allow(runner).to receive(:dry_run?).and_return(true)

    expect(seeded).to eq([])
  end
end
