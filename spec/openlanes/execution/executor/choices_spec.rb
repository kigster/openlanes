# frozen_string_literal: true

# The executor's answers about profiles, clocks and replacements, each of
# which lives in Preferences. Asked of the executor, so a caller that reached
# them before the cut still can.
RSpec.describe OpenLanes::Execution::Executor::Choices do
  subject(:executor) { OpenLanes::Execution::Executor.new(root: Dir.pwd, spawn: ->(*) {}, model: "sonnet") }

  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:reviewer) { OpenLanes::Agents.find("staff-reviewer") }
  let(:ordinal) { OpenLanes::Plans::Ordinal.parse("001.00") }

  it "answers the agent's profile, on the run's model" do
    profile = executor.profile_for(agent)
    expect([profile.adapter.name, profile.model]).to eq(["claude", "sonnet"])
  end

  it "answers the agent's clock" do
    expect(executor.timeout_for(agent)).to eq(agent.timeout || OpenLanes::Execution::Executor::DEFAULT_TIMEOUT)
  end

  it "remembers a model preferred for an agent on a plan" do
    subject_plan = Struct.new(:feature).new(Struct.new(:ordinal).new(ordinal))
    executor.prefer_model(ordinal, agent.name, "opus")
    expect(executor.preferred_model(agent, subject_plan)).to eq("opus")
  end

  it "measures the diff in a checkout for an agent with a small-diff model" do
    small = agent.with(small_diff: OpenLanes::Agents::SmallDiff.new(under_lines: 300, model: "haiku", effort: "low"))
    allow(OpenLanes::Vcs::DiffSize).to receive(:lines).with("/w").and_return(12)
    expect([executor.diff_lines(small, "/w"), executor.diff_lines(agent, "/w")]).to eq([12, nil])
  end

  it "keeps the replacements per plan" do
    expect(executor.replacing?(ordinal, reviewer)).to be(false)
    executor.replace(ordinal, reviewer)
    expect(executor.replacing?(ordinal, reviewer)).to be(true)
    executor.end_replacements(ordinal)
    expect(executor.replacing?(ordinal, reviewer)).to be(false)
  end
end
