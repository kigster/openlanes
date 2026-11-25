# frozen_string_literal: true

# The engine claims a plan folder in alock before its agent starts, and alock
# does not know the agent is the engine's: told only "a refused acquire means
# stop", a researcher spent every round it had without writing spec.md.
RSpec.describe OpenLanes::Execution::Prompt::PlanLock do
  subject(:text) { described_class.handover("researcher", folder) }

  let(:folder) { "/repo/.plans/004.00━━⚪━━❯angled box" }

  it "gives the agent the break that takes the engine's claim, where the engine took it" do
    scope = Shellwords.escape("004.00━━⚪━━❯angled box/**")
    expect(text).to include("AGENT_ID=researcher alock break #{scope} --dir /repo/.plans")
  end

  it "breaks only the harness's claim, never another agent's" do
    expect(text).to include("holder `openlanes@…`", "Break nothing else")
  end
end
