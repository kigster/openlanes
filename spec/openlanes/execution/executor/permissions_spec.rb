# frozen_string_literal: true

# The executor's answers about tools and commands, each of which lives in
# Grants or Confinement. Asked of the executor, so the agent documentation's
# `executor.denied_for` still holds.
RSpec.describe OpenLanes::Execution::Executor::Permissions do
  subject(:executor) { OpenLanes::Execution::Executor.new(root: Dir.pwd, spawn: ->(*) {}) }

  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:grants) { OpenLanes::Execution::Executor::Grants }

  it "withholds what Grants withholds" do
    expect(executor.denied_for(agent)).to eq(grants.denied_for(agent))
    expect(executor.denied_for(agent)).to include("WebFetch", "WebSearch")
  end

  it "forbids the commands Grants forbids" do
    expect(executor.denied_commands(agent)).to eq(grants.denied_commands(agent))
    expect(executor.denied_commands(agent)).to include("git push", "gh pr merge")
  end

  it "grants what the agent may have, never the ungrantable" do
    expect(executor.granted_to(agent)).to eq(grants.granted_to(agent))
    expect(executor.granted_to(agent)).not_to include(*OpenLanes::Execution::Executor::UNGRANTABLE)
  end

  it "confines what Confinement confines" do
    confined = agent.with(confined_to: %w[spec.md])
    subject_plan = Struct.new(:feature).new(Struct.new(:path).new("/plans/001.00-task"))
    expect(executor.allowed_for(confined, subject_plan))
      .to eq(OpenLanes::Execution::Executor::Confinement.allowed_for(confined, subject_plan))
    expect(executor.allowed_for(confined, subject_plan)).to include(a_string_matching(%r{\AEdit\(/+plans/001\.00-task/spec\.md\)\z}))
  end
end
