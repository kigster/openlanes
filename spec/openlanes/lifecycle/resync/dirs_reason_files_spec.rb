# frozen_string_literal: true

# X4: a non-empty reason file is what moves a plan out of the active list.
RSpec.describe OpenLanes::Lifecycle::Resync::Dirs, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:resync) { described_class.new(tree:) }

  def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

  def under(dir) = Dir.children(File.join(plans_root, dir)).sort

  context "when an active plan holds a reason file" do
    before do
      plans do |t|
        t.plan "001.00", :planned, "waiter", files: { "spec.md" => needs("002.00") }
        t.plan "002.00",
          :blocked,
          "stale",
          files: {
            "spec.md"           => needs("003.00"),
            "blocked.md"        => "## B1\nwhat?\n",
            "trashed-reason.md" => "done elsewhere\n"
          }
        t.plan "003.00", :planned, "base", files: { "spec.md" => spec_body }
      end
    end

    it "previews the move and the rewrite without changing anything" do
      expect(resync.call.map(&:target_name)).to include(match(%r{\Atrashed/002\.00━━🚮━━❯\[\d{4}-\d{2}-\d{2}\]━━stale\z}))
      expect(resync.edits.map(&:to_s)).to eq(["001.00: 002.00 → 003.00"])
      expect(Dir.exist?(File.join(plans_root, "trashed"))).to be(false)
      expect(tree.reload.find("001.00").read("spec.md")).to include('"002.00"')
    end

    context "when committed" do
      before { resync.call(commit: true) }

      it "moves it, dated today, and rewires its dependents" do
        expect(under("trashed")).to include("002.00━━🚮━━❯[#{Date.today.strftime("%F")}]━━stale")
        expect(OpenLanes::Plans::Spec.for(tree.reload.find("001.00")).depends_on).to eq(["003.00"])
      end

      it "explains the directory in a README that is not taken for a plan" do
        expect(File.read(File.join(plans_root, "trashed", "README.md"))).to include("Abandoned", "Discarded", "Trashed")
        expect(tree.everything.reload.skipped).to be_empty
      end

      it "brings the plan back when the reason file is deleted, without rewiring" do
        everything = tree.everything.reload
        File.delete(File.join(everything.find("002.00").feature.path, "trashed-reason.md"))
        described_class.new(tree:).call(commit: true)
        expect(tree.reload.find("002.00").status.key).to eq(:blocked)
        expect(OpenLanes::Plans::Spec.for(tree.find("001.00")).depends_on).to eq(["003.00"])
      end
    end

    it "touches only the plans it was told to" do
      File.write(File.join(tree.find("003.00").feature.path, "abandoned-reason.md"), "stalled")
      described_class.new(tree:, only: ["003.00"]).call(commit: true)
      expect(under("abandoned").grep(/003\.00/).size).to eq(1)
      expect(tree.reload.find("002.00")).not_to be_nil
    end
  end

  it "ignores a whitespace-only reason file" do
    plans { |t| t.plan "001.00", :new, "kept", files: { "spec.md" => spec_body, "trashed-reason.md" => " \n" } }
    expect(resync.call).to be_empty
  end

  it "moves a discarded plan out of abandoned/, keeping its date" do
    plans do |t|
      t.plan "001.00", :discarded, "old", under: "abandoned", archived_on: Date.new(2026, 9, 3), files: { "discarded.md" => "no" }
      t.plan "002.00", :abandoned, "stalled", under: "abandoned", archived_on: Date.new(2026, 9, 4), files: { "abandoned-reason.md" => "stalled" }
    end
    resync.call(commit: true)
    expect(under("discarded")).to include("001.00━━❌━━❯[2026-09-03]━━old")
    expect(under("abandoned")).to include("002.00━━👎━━❯[2026-09-04]━━stalled")
  end
end
