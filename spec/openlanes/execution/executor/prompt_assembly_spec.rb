# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::PromptAssembly, :tree do
  subject(:assembly) { described_class.new(options, preferences) }

  let(:options) { OpenLanes::Execution::Executor::Options.new(root:, packets:, memory: false, instructions: "Prefer the parser") }
  let(:preferences) { OpenLanes::Execution::Executor::Preferences.new(model: nil, timeout: 77, usable: OpenLanes::Agents::Dealing::ANY) }
  let(:packets) { nil }
  let(:root) { File.dirname(plans_root) }
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:reviewer) { OpenLanes::Agents.find("staff-reviewer") }
  let(:plan) do
    plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end
  let(:profile) { OpenLanes::Agents::Profile.new(adapter: OpenLanes::Adapters.for("claude"), model: "opus", effort: "high") }
  let(:attempt) do
    OpenLanes::Execution::Executor::Attempt.new(agent:, subject: plan, root:, profile:, trace: nil, handle: nil, sessions: nil)
  end
  let(:request) { OpenLanes::Execution::Executor::Request.new(root:, round: 3) }

  it "tells the agent what run --prompt typed" do
    expect(assembly.prompt_for(attempt, request)).to include("Prefer the parser")
  end

  it "states the clock the preferences give the agent" do
    expect(assembly.prompt_for(attempt, request)).to include("Time budget - 77 seconds")
  end

  it "tells nothing of the lessons when memory is off" do
    expect(assembly.lessons_for(agent)).to eq("")
  end

  context "with a packet builder" do
    let(:packets) { ->(_subject) { "the packet" } }

    it "hands a reviewer its packet" do
      expect(assembly.packet_for(reviewer, plan, nil)).to eq("the packet")
    end

    it "hands a builder none" do
      expect(assembly.packet_for(agent, plan, nil)).to eq("")
    end

    it "hands none to a reviewer resolving a rebase" do
      expect(assembly.packet_for(reviewer, plan, :stopped)).to eq("")
    end
  end

  context "when the packet cannot be built" do
    let(:packets) { ->(_subject) { raise OpenLanes::Error, "gh is down" } }

    it "costs the reviewer its packet, not the round" do
      expect(assembly.packet_for(reviewer, plan, nil)).to eq("")
    end
  end
end
