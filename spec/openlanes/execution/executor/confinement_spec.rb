# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Confinement do
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:plan) { Struct.new(:feature).new(Struct.new(:path).new("/plans/001.00")) }

  it "leaves an unconfined agent its own allowed tools" do
    expect(described_class.allowed_for(agent, plan)).to eq(agent.allowed_tools)
  end

  it "gives a confined agent Edit on its files by absolute path, and nothing else that writes" do
    confined = agent.with(confined_to: %w[spec.md])
    expect(described_class.allowed_for(confined, plan)).to start_with("Read", "Grep", "Glob", "Edit(//plans/001.00/spec.md)")
  end

  it "lets a confined agent run only listed commands and its ledger" do
    commands = described_class.allowed_for(agent.with(confined_to: %w[spec.md]), plan).grep(/\ABash/)
    expect(commands).to eq(["Bash(#{described_class::CONFINED_CLI}:*)", "Bash(ls:*)", "Bash(git status:*)"])
  end
end
