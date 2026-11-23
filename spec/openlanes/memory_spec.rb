# frozen_string_literal: true

# Where the operator's own lessons live. The suite overrides it outright
# (spec_helper), so these examples pass their own env.
RSpec.describe OpenLanes::Memory do
  describe ".global_dir" do
    it "prefers $OPENLANES_MEMORY_HOME" do
      expect(described_class.global_dir(env: { "OPENLANES_MEMORY_HOME" => "/srv/lessons" })).to eq("/srv/lessons")
    end

    it "uses the XDG config directory" do
      expect(described_class.global_dir(env: { "XDG_CONFIG_HOME" => "/cfg" })).to eq("/cfg/openlanes/memory/lessons")
    end

    it "falls back to ~/.config when XDG_CONFIG_HOME is unset or relative, as the XDG spec requires" do
      home = File.join(Dir.home, ".config", "openlanes", "memory", "lessons")
      expect([described_class.global_dir(env: {}), described_class.global_dir(env: { "XDG_CONFIG_HOME" => "cfg" })])
        .to eq([home, home])
    end
  end

  describe ".global_inbox_dir" do
    it "is inside the global lessons directory, so an override owns both" do
      expect(described_class.global_inbox_dir(env: { "OPENLANES_MEMORY_HOME" => "/srv/lessons" })).to eq("/srv/lessons/inbox")
    end
  end

  # C3, end to end through git: merged lessons are mirrored, a lesson two
  # projects hold turns active, and a project is not told its own lesson twice.
  describe ".mirror" do
    let(:home) { Dir.mktmpdir("global-memory") }
    let(:env) { { "OPENLANES_MEMORY_HOME" => home } }
    let(:roots) { Array.new(3) { Dir.mktmpdir("project") } }
    let(:coder) { OpenLanes::Agents.find("backend-coder") }

    after { FileUtils.rm_rf([home, *roots]) }

    def merged_project(root, remote, lesson: true)
      write_lesson(File.join(root, described_class::PROJECT_DIR), "L-0001-real-trees", lesson_meta("L-0001", title: "Specs build real trees")) if lesson
      publish_lessons(root)
      lessons_git(root, "remote", "add", "origin", remote)
      root
    end

    it "mirrors only what the default branch holds" do
      root = merged_project(roots[0], "git@github.com:example/one.git", lesson: false)
      write_lesson(File.join(root, described_class::PROJECT_DIR), "L-0002-unmerged", lesson_meta("L-0002"))

      expect(described_class.mirror(root:, env:)).to eq([])
    end

    it "is nothing where there is no default branch to read" do
      expect(described_class.mirror(root: roots[0], env:)).to eq([])
    end

    it "turns a lesson global once two projects merged it, and tells only the other projects" do
      one = merged_project(roots[0], "git@github.com:example/one.git")
      two = merged_project(roots[1], "https://github.com/example/two.git")
      three = merged_project(roots[2], "git@github.com:example/three.git", lesson: false)

      kinds = [described_class.mirror(root: one, env:), described_class.mirror(root: two, env:)].flatten.map(&:kind)
      ids = [one, three].map { |root| described_class.library(root:, env:).lessons.map(&:id) }

      expect([kinds, ids]).to eq([%i[candidate activate], [["L-0001"], ["G-0001"]]])
      expect(described_class.section(agent: coder, library: described_class.library(root: three, env:))).to include("G-0001 (medium) Specs build real trees")
    end
  end

  describe ".publication" do
    it "promotes against the default branch, through the publisher it is handed" do
      publisher = instance_double(OpenLanes::Vcs::Publisher)
      allow(OpenLanes::Vcs).to receive(:default_branch).and_return("trunk")
      allow(OpenLanes::Memory::Publication).to receive(:new).and_call_original

      expect(described_class.publication(root: "/tmp/project", publisher:)).to be_a(OpenLanes::Memory::Publication)
      expect(OpenLanes::Memory::Publication).to have_received(:new).with(root: "/tmp/project", publisher:, base: "trunk", dry_run: false)
    end
  end

  describe ".ignored" do
    it "is empty where git cannot be run" do
      allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT)
      expect(described_class.ignored(root: "/tmp/project")).to eq([])
    end
  end

  describe ".library" do
    let(:root) { Dir.mktmpdir("project") }
    let(:global) { ENV.fetch("OPENLANES_MEMORY_HOME") }
    let(:coder) { OpenLanes::Agents.find("backend-coder") }

    after do
      FileUtils.rm_rf(root)
      FileUtils.rm_rf(Dir.glob(File.join(global, "*")))
    end

    it "reads the project's merged lessons and the global ones, and gives one agent its section" do
      write_lesson(File.join(root, described_class::PROJECT_DIR), "L-1", lesson_meta("L-1", title: "Project rule"))
      write_lesson(global, "G-1", lesson_meta("G-1", title: "Operator rule"))
      publish_lessons(root)

      library = described_class.library(root:)
      expect(described_class.section(agent: coder, library:)).to include("L-1 (medium) Project rule", "G-1 (medium) Operator rule")
      expect(library.problems).to eq([])
    end

    it "reads no project lessons from a checkout with no origin, and says why" do
      write_lesson(File.join(root, described_class::PROJECT_DIR), "L-1", lesson_meta("L-1"))
      write_lesson(global, "G-1", lesson_meta("G-1"))

      library = described_class.library(root:)
      expect(library.lessons.map(&:id)).to eq(["G-1"])
      expect(library.problems).to eq(["project lessons skipped: no origin/main to read reviewed ones from"])
    end
  end

  # The facade's wiring: a real inbox decides eligibility; the publication is injected.
  describe ".autopromotion" do
    let(:root) { Dir.mktmpdir("autopromotion") }
    let(:github) { instance_double(OpenLanes::Vcs::GitHub, pulls: []) }
    let(:published) { [] }
    let(:publication) { -> { published.push(true).then { OpenLanes::Memory::Publication::Result.new(branch: "memory/x", url: "u", changes: [], held_back: []) } } }

    after { FileUtils.rm_rf(root) }

    def propose(plan)
      proposal = OpenLanes::Memory::Proposal.new(slug: "redis-specs",
        title: "Run redis specs alone",
        applies_to: ["build"],
        checked_by: [],
        kind: "pitfall",
        severity: "high",
        finding: "F1",
        body: "They race.")
      described_class.inbox(root:).add(proposal, plan:)
    end

    it "publishes once a candidate has been seen on two plans" do
      propose("001.00")
      propose("002.00")

      expect(described_class.autopromotion(root:, github:, publication:).call.status).to eq(:published)
      expect(published).to eq([true])
    end

    it "leaves a candidate seen once where it is" do
      propose("001.00")

      expect(described_class.autopromotion(root:, github:, publication:).call.status).to eq(:skipped)
      expect(published).to eq([])
    end
  end
end
