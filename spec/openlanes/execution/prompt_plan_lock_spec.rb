# frozen_string_literal: true

# Every agent prompt carries the plan-folder handover ({Prompt::PlanLock}).
RSpec.describe OpenLanes::Execution::Prompt, :tree do
  let(:profile) { OpenLanes::Agents::Profile.resolve(agent) }
  let(:agent) { OpenLanes::Agents.find("researcher") }
  let(:plan) do
    plans { |t| t.plan "004.00", :new, "angled-box", files: { "spec.md" => "# Box\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end

  it "tells every agent how to take over its plan folder's claim" do
    text = described_class.new(agent:, subject: plan, root: "/repo", profile:).to_s
    expect(text).to include("AGENT_ID=researcher alock break", "--dir #{Shellwords.escape(plans_root)}")
  end
end
