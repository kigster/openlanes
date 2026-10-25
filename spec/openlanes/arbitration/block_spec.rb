# frozen_string_literal: true

# ⭕️'s invariant wants blocked.md before the move, so the file is written
# first; what is under test is that a move that does not happen leaves the
# folder as it found it.
RSpec.describe OpenLanes::Arbitration, ".block", :tree do
  let(:question) { "# Blocked\n\n## B1 Go on?\n\na) Yes. (Recommended)\nb) No.\n" }

  def plan = OpenLanes::Plans::Tree.new(dir: plans_root).find("015.00")
  def blocked = File.join(plan.feature.path, "blocked.md")

  context "with a plan at 🔴" do
    before { plans { |t| t.plan "015.00", :rejected, "arbiter", files: { "spec.md" => spec_body, "plan.md" => "## U1" } } }

    it "writes blocked.md and moves the plan to ⭕️" do
      expect([described_class.block(plan, question), plan.status.key, plan.read("blocked.md")]).to eq([true, :blocked, question])
    end

    it "takes blocked.md back when the machine refuses the move" do
      expect([described_class.block(plan, "# Blocked\n\nnothing to ask\n"), plan.status.key, File.exist?(blocked)]).to eq([false, :rejected, false])
    end

    it "puts back a blocked.md that was there before" do
      File.write(blocked, "kept\n")
      described_class.block(plan, "# Blocked\n\nnothing to ask\n")
      expect(File.read(blocked)).to eq("kept\n")
    end
  end

  it "writes nothing for a plan at 👀, which has no edge to ⭕️" do
    plans { |t| t.plan "015.00", :in_review, "arbiter", files: { "spec.md" => spec_body, "plan.md" => "## U1" } }
    expect([described_class.block(plan, question), plan.status.key, File.exist?(blocked)]).to eq([false, :in_review, false])
  end
end
