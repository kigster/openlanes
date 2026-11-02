# frozen_string_literal: true

require "open3"

# What the whole-branch review of plan 059 found, each pinned where it bit.
RSpec.describe OpenLanes::Lifecycle::Removal, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:everything) { tree.everything }

  def rewiring = OpenLanes::Lifecycle::Rewiring.new(tree:)

  def two_plans(dependent_spec)
    plans do |t|
      t.plan "001.00", :planned, "a", files: { "spec.md" => dependent_spec, "plan.md" => "## U\n" }
      t.plan "002.00", :planned, "b", files: { "spec.md" => "---\ndepends_on: [\"003.00\"]\n---\nb\n", "plan.md" => "## U\n" }
      t.plan "003.00", :planned, "c", files: { "spec.md" => "c\n", "plan.md" => "## U\n" }
    end
  end

  def spec_of(ordinal) = tree.reload.find(ordinal).read("spec.md")

  describe "C1: frontmatter survives the rewrite" do
    it "rewrites a list at column zero" do
      two_plans("---\ndepends_on:\n- \"002.00\"\nlane: quick\n---\nbody\n")
      rewiring.then { it.apply(it.plan(["002.00"])) }
      expect(spec_of("001.00")).to eq("---\ndepends_on: [\"003.00\"]\nlane: quick\n---\nbody\n")
    end

    it "rewrites a flow list across several lines" do
      two_plans("---\ndepends_on: [\n  \"002.00\"\n]\nlane: quick\n---\nbody\n")
      rewiring.then { it.apply(it.plan(["002.00"])) }
      expect(spec_of("001.00")).to eq("---\ndepends_on: [\"003.00\"]\nlane: quick\n---\nbody\n")
    end

    it "reports, and leaves alone, a list it cannot rewrite faithfully" do
      text = "---\ndepends_on:\n- \"002.00\"\n# note\n- \"004.00\"\nlane: quick\n---\nbody\n"
      two_plans(text)
      edits = rewiring.then { it.apply(it.plan(["002.00"])) }
      expect(edits.map(&:problem)).to all(include('left as written'))
      expect(spec_of("001.00")).to eq(text)
    end
  end

  describe "I6: an unparseable dependent" do
    it "is reported when it names the plan by its short number" do
      text = "---\ndepends_on: [002\n---\nbody\n"
      two_plans(text)
      expect(rewiring.plan(["002.00"]).map(&:problem)).to all(include('did not parse')).and(have_attributes(size: 1))
    end
  end

  describe "I2: a reason already written" do
    before { plans { |t| t.plan "001.00", :new, "taken", files: { "spec.md" => "x\n", "trashed-reason.md" => "my careful reason\n" } } }

    it "is kept beside the new one" do
      described_class.new(tree:, to: :trashed).call({ "001.00" => "second" })
      expect(everything.reload.find("001.00").read("trashed-reason.md")).to include("my careful reason", "second")
    end

    it "survives a refused move" do
      today = Date.today.strftime("%F")
      source = OpenLanes::Plans::Tree.new(dir: plans_root, all: true).find("001.00").feature.path
      taken = File.join(plans_root, "trashed", "001.00━━🚮━━❯[#{today}]━━taken")
      FileUtils.mkdir_p(taken)
      FileUtils.touch(File.join(taken, "x"))
      result = described_class.new(tree:, to: :trashed).call({ "001.00" => "second" })
      expect(result.refused.keys).to eq(["001.00"])
      expect(File.read(File.join(source, "trashed-reason.md"))).to eq("my careful reason\n")
    end
  end

  describe "I3: a dependent somebody is working in" do
    before { two_plans("---\ndepends_on: [\"002.00\"]\n---\nbody\n") }

    def hand_reason = File.write(File.join(tree.find("002.00").feature.path, "trashed-reason.md"), "why")

    it "is left as written and reported, under except:" do
      hand_reason
      resync = OpenLanes::Lifecycle::Resync::Dirs.new(tree:, except: ["001.00"])
      resync.call(commit: true)
      expect(spec_of("001.00")).to include('"002.00"')
      expect(resync.edits.map(&:to_s)).to all(match(/001\.00.*left as written/))
    end

    it "is left as written under a live lock" do
      OpenLanes::Plans::Lock.write(tree.find("001.00").feature.path)
      hand_reason
      OpenLanes::Lifecycle::Resync::Dirs.new(tree:).call(commit: true)
      expect(spec_of("001.00")).to include('"002.00"')
    end
  end

  describe "I4: rewrites are logged wherever they happen" do
    it "logs each one" do
      two_plans("---\ndepends_on: [\"002.00\"]\n---\nbody\n")
      allow(OpenLanes::UI).to receive(:log)
      rewiring.then { it.apply(it.plan(["002.00"])) }
      expect(OpenLanes::UI).to have_received(:log).with(/001\.00: 002\.00 → 003\.00/)
    end
  end

  describe "I5: a hand-written reason" do
    it "records the rewrites too" do
      two_plans("---\ndepends_on: [\"002.00\"]\n---\nbody\n")
      File.write(File.join(tree.find("002.00").feature.path, "trashed-reason.md"), "my reason\n")
      OpenLanes::Lifecycle::Resync::Dirs.new(tree:).call(commit: true)
      text = everything.reload.find("002.00").read("trashed-reason.md")
      expect(text).to include("my reason", "001.00: 002.00 → 003.00")
    end
  end

  describe "C2: a plain git commit carries the removal" do
    let(:root) { File.dirname(plans_root) }

    def git(*, dir: root)
      out, status = Open3.capture2e("git", "-C", dir, "-c", "user.name=T", "-c", "user.email=t@example.com", *)
      raise out unless status.success?

      out
    end

    def clone_of
      clone = File.join(Dir.mktmpdir("openlanes-clone"), "c")
      git("clone", "-q", root, clone)
      File.join(clone, File.basename(plans_root))
    end

    before do
      two_plans("---\ndepends_on: [\"002.00\"]\n---\nbody\n")
      git("init", "-q")
      git("add", "-A")
      git("commit", "-qm", "seed")
      described_class.new(tree:, to: :trashed).call({ "002.00" => "gone" })
      git("commit", "-qm", "remove")
    end

    it "holds in a fresh clone, reason, README and rewrite together" do
      cloned = clone_of
      clone_tree = OpenLanes::Plans::Tree.new(dir: cloned)
      expect(OpenLanes::Lifecycle::Resync::Dirs.new(tree: clone_tree).plan).to be_empty
      expect(File.exist?(File.join(cloned, "trashed", "README.md"))).to be(true)
      expect(clone_tree.find("001.00").read("spec.md")).to include('"003.00"')
    end

    it "commits the restore as well" do
      File.delete(File.join(everything.reload.find("002.00").feature.path, "trashed-reason.md"))
      OpenLanes::Lifecycle::Resync::Dirs.new(tree:).call(commit: true)
      git("commit", "-qm", "restore")
      expect(OpenLanes::Plans::Tree.new(dir: clone_of).find("002.00")).not_to be_nil
    end
  end
end
