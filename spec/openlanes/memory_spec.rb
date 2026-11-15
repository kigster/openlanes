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
end
