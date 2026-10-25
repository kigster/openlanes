# frozen_string_literal: true

require "socket"

RSpec.describe OpenLanes::Engine::Recovery::Stranded, :tree do
  subject(:stranded) { described_class.new(runner:, state:, records:, clock: OpenLanes::Clock::Fake.new) }

  let(:agent) { instance_double(OpenLanes::Agents::Agent, name: "luke-backend", ledger: %w[plan.md]) }
  let(:agents) { instance_double(OpenLanes::Agents::Registry) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:runner) do
    instance_double(OpenLanes::Engine::Runner, tree:, agents:, dry_run?: false, foreign?: false, in_scope: tree.subjects, root: plans_root)
  end
  let(:records) { OpenLanes::Engine::Recovery::Records.new(dry_run: false) }
  let(:state) { nil }
  let(:path) { tree.find("003.00").feature.path }
  let(:plan_state) { OpenLanes::Plans::PlanState.for(path) }

  before do
    plans { |t| t.plan "003.00", :building, "work" }
    allow(agents).to receive(:find).with("luke-backend").and_return(agent)
    plan_state.stage!(agent: "luke-backend", round: 1, status: "Started", run: { pid: 999_999_999, host: Socket.gethostname })
  end

  it "marks a round a dead run left Started as interrupted, and tells the agent to carry on" do
    stranded.call

    aggregate_failures do
      expect(plan_state.stages.map { it["status"] }).to eq(%w[Interrupted])
      expect(plan_state.last_known("luke-backend").note).to start_with("harness died")
      expect(OpenLanes::Plans::Mailbox.new(dir: path).messages.last.body).to start_with("RESUME: the harness died during your round 1")
    end
  end

  context "with the run's own state file" do
    let(:state) do
      instance_double(OpenLanes::Engine::StateFile,
        load:       nil,
        stranded:   { "003.00" => { "agent" => "luke-backend", "round" => 1 } },
        record:     nil,
        begin_run!: nil)
    end

    it "resumes what the state file names once, even when state.json names it too, and begins the run" do
      stranded.call

      aggregate_failures do
        expect(state).to have_received(:record).with("003.00", agent: "luke-backend", round: 1, status: "Interrupted", exit: "harness died").once
        expect(state).to have_received(:begin_run!).with(root: plans_root)
      end
    end
  end

  it "skips an agent no longer defined" do
    allow(agents).to receive(:find).and_return(nil)
    stranded.call

    expect(plan_state.stages.map { it["status"] }).to eq(%w[Started])
  end
end
