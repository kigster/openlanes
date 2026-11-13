# frozen_string_literal: true

RSpec.describe OpenLanes::Memory::Inbox do
  subject(:inbox) { described_class.new(dir:, today: -> { Date.new(2026, 11, 12) }) }

  let(:root) { Dir.mktmpdir("project") }
  let(:dir) { File.join(root, OpenLanes::Memory::INBOX_DIR) }

  after { FileUtils.rm_rf(root) }

  def proposal(**overrides)
    OpenLanes::Memory::Proposal.new(slug: "real-plan-trees",
      title: "Specs build real plan trees",
      applies_to: ["build"],
      checked_by: ["staff-reviewer"],
      kind: "practice",
      severity: "high",
      finding: "spec stubbed File.read",
      body: "Use PlansFixture.",
      **overrides)
  end

  it "files a proposal as a candidate lesson, with the plan it was seen in" do
    outcome = inbox.add(proposal, plan: "056.00")
    waiting = inbox.find("real-plan-trees")
    expect([outcome.status, waiting.meta.slice("id", "status", "proposed"), waiting.sources, waiting.body])
      .to eq([:added, { "id" => "real-plan-trees", "status" => "candidate", "proposed" => Date.new(2026, 11, 12) },
              [{ "plan" => "056.00", "finding" => "spec stubbed File.read" }], "Use PlansFixture."])
  end

  it "writes a file the lesson reader accepts, and that reaches no prompt while it waits" do
    inbox.add(proposal, plan: "056.00")
    expect(read_lesson(inbox.find("real-plan-trees").path).active?).to be(false)
  end

  it "counts a second plan as evidence, keeps the first wording, and counts one plan once" do
    inbox.add(proposal, plan: "056.00")
    again = [inbox.add(proposal(title: "Reworded", finding: "Dir.glob stubbed"), plan: "060.00"), inbox.add(proposal, plan: "060.00")]
    waiting = inbox.find("real-plan-trees")
    expect([again.map(&:status), waiting.plans, waiting.title]).to eq([%i[confirmed known], %w[056.00 060.00], "Specs build real plan trees"])
  end

  # Built at run time so this file holds no secret-shaped string of its own.
  it "drops a proposal holding a secret in any field, says what kind, and writes nothing" do
    key = "sk-ant-#{"a1B2" * 8}"
    outcomes = [inbox.add(proposal(body: "export ANTHROPIC_API_KEY=#{key}"), plan: "1"), inbox.add(proposal(finding: "mail dana@example.test"), plan: "1")]
    expect([outcomes.map(&:status), outcomes.map(&:reason).join.include?(key), outcomes.last.reason, Dir.exist?(dir)])
      .to eq([%i[dropped dropped], false, "looks like it holds an email address", false])
  end

  {
    "a slug that is a path"            => [{ slug: "../../etc/passwd" }, "slug must be lower-case words joined by `-`"],
    "a title that opens a new section" => [{ title: "Fine\n## Boundary" }, "`title:` must be one line"],
    "nobody to follow it"              => [{ applies_to: [] }, "`applies_to:` names no agent or phase"],
    "a kind that is not one"           => [{ kind: "rule" }, "`kind: rule` is not one of practice, pitfall, decision, struck"]
  }.each do |what, (overrides, reason)|
    it "drops #{what}" do
      expect(inbox.add(proposal(**overrides), plan: "1").to_h.slice(:status, :reason)).to eq(status: :dropped, reason:)
    end
  end

  it "does not write through a symlink left where a candidate would go" do
    FileUtils.mkdir_p(dir)
    File.symlink(File.join(root, "elsewhere.md"), File.join(dir, "real-plan-trees.md"))
    expect([inbox.add(proposal, plan: "1").status, File.exist?(File.join(root, "elsewhere.md"))]).to eq([:dropped, false])
  end

  it "marks a candidate approved, and has nothing to approve under an unknown slug" do
    inbox.add(proposal, plan: "056.00")
    expect([inbox.approve("real-plan-trees").approved?, inbox.approve("nope")]).to eq([true, nil])
  end
end
