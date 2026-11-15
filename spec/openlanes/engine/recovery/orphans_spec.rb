# frozen_string_literal: true

require "socket"

RSpec.describe OpenLanes::Engine::Recovery::Orphans, :tree do
  subject(:orphans) { described_class.new.call(plan).map { it.values_at("agent", "round") } }

  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:plan) { tree.reload.find("003.00") }
  let(:plan_state) { OpenLanes::Plans::PlanState.for(plan.feature.path) }

  def started(agent, round, **fields)
    plan_state.stage!(agent:, round:, reset: true, status: "Started", from: "building", state: "building", **fields)
  end

  before do
    plans { |t| t.plan "003.00", :building, "work" }
    plan_state.state!(:building)
  end

  it "finds nothing on a plan with no round under way" do
    plan_state.stage!(agent: "backend-coder", round: 1, reset: true, status: "Completed", from: "building", state: "building")

    expect(orphans).to eq([])
  end

  it "names each round of the current visit still Started" do
    started("backend-coder", 2)
    started("frontend-coder", 1)

    expect(orphans).to eq([["backend-coder", 2], ["frontend-coder", 1]])
  end

  it "leaves a round of an earlier visit alone: it holds nobody back" do
    started("backend-coder", 1)
    plan_state.state!(:built)
    plan_state.state!(:building)

    expect(orphans).to eq([])
  end

  it "leaves a stage that names its run to the check of that run's pid" do
    started("backend-coder", 1, run: { pid: 999_999_999, host: Socket.gethostname })

    expect(orphans).to eq([])
  end

  context "when another live run holds the plan's lock" do
    # The suite's parent process: alive, and not this one.
    before { OpenLanes::Plans::Lock.write(plan.feature.path, pid: Process.ppid) }

    after { OpenLanes::Plans::Lock.remove(plan.feature.path) }

    it "finds nothing: the Started round is that run's agent, working" do
      started("backend-coder", 1)

      expect(orphans).to eq([])
    end
  end
end
