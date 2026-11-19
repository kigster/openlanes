# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Grants do
  let(:agent) { OpenLanes::Agents.find("backend-coder") }

  it "withholds the network tools from an agent that did not ask for them" do
    expect(described_class.denied_for(agent.with(network: false))).to include("WebFetch", "WebSearch")
  end

  it "leaves them to an agent that declares network: true" do
    expect(described_class.denied_for(agent.with(network: true))).not_to include("WebFetch")
  end

  it "lifts what may: grants" do
    expect(described_class.denied_commands(agent.with(may: ["gh pr review"]))).not_to include("gh pr review")
  end

  it "never lifts what is ungrantable, whatever may: says" do
    granted = agent.with(may: described_class::UNGRANTABLE)
    expect(described_class.denied_commands(granted)).to include(*described_class::UNGRANTABLE)
  end

  it "is what the executor still names under its own constants" do
    expect(OpenLanes::Execution::Executor::FORBIDDEN_COMMANDS).to equal(described_class::FORBIDDEN_COMMANDS)
  end
end
