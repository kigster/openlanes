# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::ReviewPacket, :tree do
  let(:github) { instance_double(OpenLanes::Vcs::GitHub, pr_diff: "+ added line\n") }
  let(:sha) { +"abc123" }
  let(:head) { ->(_checkout) { sha } }
  let(:spec_md) { "---\nstarts: planning\n---\n\n## What needs to be done\n\n1. Cut the round trips.\n\n## Why\n\nSpeed.\n" }
  let(:plan_md) { "## Backend\n\n### B1 Packet\n\n### B2 Gate\n" }
  let(:files) { { "spec.md" => spec_md, "plan.md" => plan_md } }
  let(:plan) do
    plans { |t| t.plan "001.00", :ready_for_review, "work", files:, prs: [t.open(7, "[001.00] Work")] }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end

  before { described_class.reset! }

  def build = described_class.build(plan, "/checkout", github:, head:)

  it "builds the diff once for three reviewers on the same head" do
    packets = Array.new(3) { build }
    expect(packets.map(&:head_sha).uniq).to eq(["abc123"])
    expect(github).to have_received(:pr_diff).once.with(number: "7")
  end

  it "builds again when the head moves" do
    build
    sha.replace("def456")
    expect(build.head_sha).to eq("def456")
    expect(github).to have_received(:pr_diff).twice
  end

  it "digests the spec's work, the plan's units and the pull request row" do
    digest = build.digest
    expect(digest).to include("1. Cut the round trips.", "- B1 Packet", "- B2 Gate", "#7 — [001.00] Work")
    expect(digest).not_to include("Speed.")
  end

  it "carries contract.md when the plan has one, and leaves it out when not" do
    expect(build.digest).not_to include("contract.md")
    described_class.reset!
    File.write(File.join(plan.feature.path, "contract.md"), "GET /board returns rows")
    plan.reread!
    expect(build.digest).to include("#### contract.md", "GET /board returns rows")
  end

  it "caps the diff and says so" do
    allow(github).to receive(:pr_diff).and_return("x" * (described_class::MAX_DIFF + 10))
    packet = build
    expect([packet.diff.size, packet.truncated, packet.to_prompt]).to match([described_class::MAX_DIFF, true, include("truncated")])
  end

  it "tells the reviewer not to fetch a diff it already has" do
    expect(build.to_prompt).to include("Review packet, head abc123", "+ added line", "do not run `gh pr diff`")
  end

  it "has no diff for a plan with no open pull request" do
    plans { |t| t.plan "002.00", :ready_for_review, "solo", files: }
    solo = OpenLanes::Plans::Tree.new(dir: plans_root).subjects.find { it.feature.ordinal.to_s == "002.00" }
    expect(described_class.build(solo, "/checkout", github:, head:).diff).to eq("")
  end

  it "reads the checkout's HEAD through git" do
    expect(described_class.head_of(Dir.pwd)).to match(/\A\h{40}\z/)
  end

  it "answers nil for a directory that is no checkout" do
    expect(described_class.head_of(plans_root)).to be_nil
  end
end
