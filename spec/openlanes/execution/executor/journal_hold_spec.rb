# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::JournalHold, :tree do
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:plan) do
    plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end
  let(:handle) { OpenLanes::Execution::Executor::Handle.new.tap { it.session = session } }
  let(:session) { "sess-1" }
  let(:sessions) { OpenLanes::Execution::Executor::Sessions.new }
  let(:attempt) do
    OpenLanes::Execution::Executor::Attempt.new(agent:, subject: plan, root: plans_root, profile: nil, trace: nil, handle:, sessions:)
  end
  let(:state) { -> { OpenLanes::Plans::PlanState.for(plan.feature.path) } }

  def held = state.call.held(agent.name)

  it "records the session that holds the journal" do
    described_class.hold(attempt)
    expect(held).not_to be_nil
  end

  it "forgets it again" do
    described_class.hold(attempt)
    described_class.forget(agent, plan)
    expect(held).to be_nil
  end

  context "without a session" do
    let(:session) { nil }

    it "records nothing" do
      described_class.hold(attempt)
      expect(held).to be_nil
    end
  end

  it "records nothing for a folder renamed under the agent" do
    FileUtils.rm_rf(plan.feature.path)
    described_class.hold(attempt)
    expect(File.directory?(plan.feature.path)).to be(false)
  end
end
