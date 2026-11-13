# frozen_string_literal: true

# Plan 060, B1: reviewers read one packet the harness built, rather than each
# gathering the plan and the diff for itself.
RSpec.describe OpenLanes::Execution::Prompt, :tree do
  let(:github) { instance_double(OpenLanes::Vcs::GitHub, pr_diff: "+ the change\n") }
  let(:packet) { ->(plan, root) { OpenLanes::Engine::ReviewPacket.build(plan, root, github:, head: ->(_) { "feed42" }) } }
  let(:plan) do
    plans do |t|
      t.plan "001.00",
        :ready_for_review,
        "task",
        files: { "spec.md" => "## What needs to be done\n\n1. Ship it.\n", "plan.md" => "### B1 Ship\n" },
        prs:   [t.open(9, "[001.00] Task")]
    end
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end

  before { OpenLanes::Engine::ReviewPacket.reset! }

  def prompt_for(name, packet: self.packet)
    agent = OpenLanes::Agents.find(name)
    described_class.new(agent:, subject: plan, root: File.dirname(plans_root), profile: OpenLanes::Agents::Profile.resolve(agent), packet:).to_s
  end

  it "hands all three reviewers the same packet, from one diff fetch" do
    prompts = %w[staff-reviewer security-reviewer design-reviewer].map { prompt_for(it) }
    expect(prompts).to all(include("Review packet, head feed42", "+ the change", "1. Ship it.", "- B1 Ship"))
    expect(github).to have_received(:pr_diff).once
  end

  it "gives a builder no packet" do
    expect(prompt_for("backend-coder")).not_to include("Review packet")
  end

  it "leaves the packet out when it cannot be built, so the reviewer gathers it itself" do
    failing = ->(*) { raise OpenLanes::Error, "gh is down" }
    expect(prompt_for("staff-reviewer", packet: failing)).not_to include("Review packet")
  end
end
