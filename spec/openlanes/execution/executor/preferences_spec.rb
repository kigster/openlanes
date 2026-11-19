# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Preferences do
  subject(:preferences) { described_class.new(model: "sonnet", timeout:, usable: OpenLanes::Agents::Dealing::ANY) }

  let(:timeout) { nil }
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:plan) { Struct.new(:feature).new(Struct.new(:ordinal).new("001.00")) }

  it "has no preferred model until one is chosen" do
    expect(preferences.preferred_model(agent, plan)).to be_nil
  end

  it "keeps a model chosen for one agent on one plan, and forgets it on nil" do
    preferences.prefer_model("001.00", agent.name, "opus")
    chosen = preferences.preferred_model(agent, plan)
    preferences.prefer_model("001.00", agent.name, nil)
    expect([chosen, preferences.preferred_model(agent, plan)]).to eq(["opus", nil])
  end

  it "has no preferred model without a plan" do
    expect(preferences.preferred_model(agent, nil)).to be_nil
  end

  it "measures no diff for an agent without a small_diff model" do
    expect(preferences.diff_lines(agent.with(small_diff: nil), "/nowhere")).to be_nil
  end

  context "with --timeout tighter than the agent's own" do
    let(:timeout) { 60 }

    it "takes the tighter" do
      expect(preferences.timeout_for(agent.with(timeout: 600))).to eq(60)
    end
  end

  it "falls back to the default when neither names a figure" do
    expect(preferences.timeout_for(agent.with(timeout: nil))).to eq(OpenLanes::Execution::Executor::DEFAULT_TIMEOUT)
  end

  it "resolves the --model typed when nothing was preferred" do
    expect(preferences.profile_for(agent, nil, root: Dir.pwd).model).to eq("sonnet")
  end
end
