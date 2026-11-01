# frozen_string_literal: true

# X2, X4, X7: from any state, with a reason, and never halfway.
RSpec.describe OpenLanes::Lifecycle::Removal, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:today) { Date.today.strftime("%F") }
  let(:open_pr) { "| Pull Request Number | Pull Request Name | Status |\n| -: | :- | -: |\n| 12 | [x](https://github.com/o/r/pull/12) | Open 🟢 |\n" }

  def removal(to) = described_class.new(tree:, to:)

  def folder(ordinal) = tree.everything.reload.find(ordinal).feature

  def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

  {
    "an unanswered block" => [:blocked, { "blocked.md" => "## B1\nwhat?\n" }],
    "no plan"             => [:new, { "spec.md" => "# x\n" }],
    "a legacy name"       => [:new, {}]
  }.each do |what, (state, files)|
    it "trashes a plan with #{what}" do
      plans { |t| t.plan "001.00", state, "stale", files: }
      removal(:trashed).call({ "001.00" => "done elsewhere" })
      expect(folder("001.00").dirname).to eq("001.00━━🚮━━❯[#{today}]━━stale")
      expect(File.dirname(folder("001.00").path)).to end_with("/trashed")
    end
  end

  it "records the reason literally, with the date and the previous state" do
    plans { |t| t.plan "001.00", :blocked, "stale", files: { "blocked.md" => "## B1\nwhat?\n" } }
    reason = "it's \"done\"\n\n- with *markdown*\n"
    removal(:trashed).call({ "001.00" => reason })
    text = File.read(File.join(folder("001.00").path, "trashed-reason.md"))
    expect(text).to include(reason.strip, "Date: #{today}", "Previous state: ⭕ Technical Block")
  end

  it "records the rewrites in the reason file and reports them" do
    plans do |t|
      t.plan "001.00", :planned, "waiter", files: { "spec.md" => needs("002.00") }
      t.plan "002.00", :planned, "gone", files: { "spec.md" => needs("003.00") }
      t.plan "003.00", :planned, "base", files: { "spec.md" => spec_body }
    end
    result = removal(:abandoned).call({ "002.00" => "stalled" })
    expect(result.edits.map(&:to_s)).to eq(["001.00: 002.00 → 003.00"])
    expect(File.read(File.join(folder("002.00").path, "abandoned-reason.md"))).to include("001.00: 002.00 → 003.00")
    expect(OpenLanes::Plans::Spec.for(tree.reload.find("001.00")).depends_on).to eq(["003.00"])
  end

  it "skips a plan already there and keeps its reason" do
    plans { |t| t.plan "001.00", :trashed, "gone", under: "trashed", files: { "trashed-reason.md" => "first" } }
    result = removal(:trashed).call({ "001.00" => "second" })
    expect(result.skipped).to eq(["001.00"])
    expect(File.read(File.join(folder("001.00").path, "trashed-reason.md"))).to eq("first")
  end

  it "trashes a discarded plan and keeps its first reason" do
    plans { |t| t.plan "001.00", :discarded, "no", under: "discarded", files: { "discarded-reason.md" => "decided" } }
    removal(:trashed).call({ "001.00" => "clearing" })
    expect(Dir.children(folder("001.00").path)).to include("discarded-reason.md", "trashed-reason.md")
    expect(folder("001.00").status.key).to eq(:trashed)
  end

  it "refuses to discard what is trashed" do
    plans { |t| t.plan "001.00", :trashed, "gone", under: "trashed", files: { "trashed-reason.md" => "first" } }
    result = removal(:discarded).call({ "001.00" => "x" })
    expect(result.refused.keys).to eq(["001.00"])
  end

  it "refuses a plan an agent holds, and still moves the others" do
    plans do |t|
      t.plan "001.00", :building, "busy", files: { "plan.md" => "## U\n" }
      t.plan "002.00", :new, "free", files: { "spec.md" => spec_body }
    end
    OpenLanes::Plans::Lock.write(folder("001.00").path)
    result = removal(:trashed).call({ "001.00" => "x", "002.00" => "y" })
    expect(result.refused.keys).to eq(["001.00"])
    expect(result.moved.map(&:ordinal)).to eq(["002.00"])
    expect(Dir.children(folder("001.00").path)).not_to include("trashed-reason.md")
  end

  it "refuses a plan whose target name is taken, removes the reason it wrote, and moves the others" do
    plans do |t|
      t.plan "001.00", :new, "taken", files: { "spec.md" => spec_body }
      t.plan "002.00", :new, "free", files: { "spec.md" => spec_body }
    end
    FileUtils.mkdir_p(File.join(plans_root, "trashed", "001.00━━🚮━━❯[#{today}]━━taken"))
    FileUtils.touch(File.join(plans_root, "trashed", "001.00━━🚮━━❯[#{today}]━━taken", "x"))
    source = tree.find("001.00").feature.path
    result = removal(:trashed).call({ "001.00" => "x", "002.00" => "y" })
    expect(result.refused.keys).to eq(["001.00"])
    expect(result.moved.map(&:ordinal)).to eq(["002.00"])
    expect(File.exist?(File.join(source, "trashed-reason.md"))).to be(false)
  end

  it "names the open pull requests it left alone" do
    plans { |t| t.plan "001.00", :ready_for_review, "pr", files: { "plan.md" => "## U\n", "pull-requests.md" => open_pr } }
    expect(removal(:trashed).call({ "001.00" => "x" }).open_prs.fetch("001.00")).to eq(["#12"])
  end

  it "changes nothing on a dry run, and says what it would do" do
    plans do |t|
      t.plan "001.00", :planned, "waiter", files: { "spec.md" => needs("002.00") }
      t.plan "002.00", :planned, "gone", files: { "spec.md" => spec_body }
    end
    before = Dir.glob("**/*", base: plans_root).sort
    result = removal(:trashed).call({ "002.00" => "x" }, dry_run: true)
    expect(result.moved.map(&:ordinal)).to eq(["002.00"])
    expect(result.edits.map(&:to_s)).to eq(["001.00: 002.00 → (nothing)"])
    expect(Dir.glob("**/*", base: plans_root).sort).to eq(before)
  end
end
