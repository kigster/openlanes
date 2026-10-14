# frozen_string_literal: true

require "json"

RSpec.describe OpenLanes::Engine::StateFile, :tree do
  subject(:state) { described_class.new(path:, pid: 4242) }

  let(:path) { File.join(plans_root, described_class::FILENAME) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }

  it "lives in .plans, beside the plan folders rather than under them" do
    expect(described_class.for(tree)).to eq(path)
  end

  it "starts empty, saves atomically, and loads what it saved" do
    state.begin_run!(root: "/repo")
    state.record("001.00", agent: "leah-researcher", round: 1, status: "Started", model: "haiku")
    state.save
    loaded = described_class.new(path:, pid: 4242).load
    aggregate_failures do
      expect(loaded.stages("001.00").first).to include("agent" => "leah-researcher", "status" => "Started", "model" => "haiku")
      expect(JSON.parse(File.read(path)).dig("run", "pid")).to eq(4242)
      expect(Dir.children(plans_root).grep(/\.tmp\z/)).to be_empty
    end
  end

  it "keeps the live run's record beside the stages, and loads it back" do
    state.live = { "seq" => 3, "held_cars" => ["001.00/luke-backend"] }
    state.save
    expect(described_class.new(path:, pid: 4242).load.live).to eq("seq" => 3, "held_cars" => ["001.00/luke-backend"])
  end

  it "merges later fields into the same stage rather than adding a second one" do
    state.record("001.00", agent: "leah-researcher", round: 1, status: "Started")
    state.record("001.00", agent: "leah-researcher", round: 1, status: "Completed", up: 12)
    expect(state.stages("001.00").size).to eq(1)
    expect(state.stages("001.00").first).to include("status" => "Completed", "up" => 12)
  end

  it "keeps a second round as its own stage" do
    state.record("001.00", agent: "leah-researcher", round: 1, status: "Interrupted")
    state.record("001.00", agent: "leah-researcher", round: 2, status: "Started")
    expect(state.stages("001.00").map { |s| s["round"] }).to eq([1, 2])
  end

  # A harness that died leaves Started stages behind; the next one must
  # know they are stranded rather than still running.
  it "reports stages a dead run left Started as stranded" do
    dead = described_class.new(path:, pid: 999_999_999)
    dead.begin_run!(root: "/repo")
    dead.record("001.00", agent: "yoda-writer", round: 1, status: "Started")
    dead.record("002.00", agent: "leah-researcher", round: 1, status: "Completed")
    dead.save

    fresh = described_class.new(path:, pid: 4242).load
    aggregate_failures do
      expect(fresh).to be_previous_run_dead
      expect(fresh.stranded.map { |ordinal, stage| [ordinal, stage["agent"]] }).to eq([["001.00", "yoda-writer"]])
    end
  end

  it "does not call a live run's Started stages stranded" do
    state.begin_run!(root: "/repo")
    state.record("001.00", agent: "yoda-writer", round: 1, status: "Started")
    state.save
    fresh = described_class.new(path:, pid: 4242).load
    expect(fresh.stranded).to be_empty
  end

  # The file moved up out of `tmp/` after runs had already written there.
  # One that died under the old layout still has to be picked up, or its
  # Started stages are invisible and it silently restarts from zero.
  describe "the file a run left in the old tmp/ directory" do
    subject(:loaded) { described_class.new(path:, pid: 4242).load }

    let(:legacy) { described_class.legacy_for(tree) }
    let(:stage) { { "agent" => "yoda-writer", "round" => 1, "status" => "Started" } }
    let(:written) { { "run" => { "pid" => 999_999_999 }, "plans" => { "001.00" => { "stages" => [stage] } } } }

    before do
      FileUtils.mkdir_p(File.dirname(legacy))
      File.write(legacy, JSON.generate(written))
    end

    it "is read when the current path holds nothing" do
      expect(loaded.stages("001.00").first).to include("agent" => "yoda-writer")
    end

    it "is still reported as stranded, so the next run knows to re-run it" do
      expect(loaded.stranded.map(&:first)).to eq(["001.00"])
    end

    it "is left on disk, being the only record that run has" do
      loaded
      expect(File.file?(legacy)).to be(true)
    end

    context "when the current path holds a run of its own" do
      before { File.write(path, JSON.generate({ "run" => {}, "plans" => { "002.00" => { "stages" => [] } } })) }

      it "loses to it" do
        expect(loaded.plans).to eq(["002.00"])
      end
    end
  end

  describe ".ensure_ignored!" do
    subject(:root) { File.dirname(plans_root) }

    it "adds both lines to .gitignore once, and says so" do
      system("git", "-C", root, "init", "-q")
      aggregate_failures do
        expect(described_class.ensure_ignored!(root)).to be(true)
        expect(File.read(File.join(root, ".gitignore"))).to include(".plans/openlanes-state.json\n")
        expect(described_class.ensure_ignored!(root)).to be(false)
      end
    end

    it "ignores the sibling save writes and renames over the file" do
      system("git", "-C", root, "init", "-q")
      described_class.ensure_ignored!(root)
      expect(File.read(File.join(root, ".gitignore"))).to include(".plans/openlanes-state.json.*.tmp\n")
    end

    it "does nothing outside a repository" do
      expect(described_class.ensure_ignored!(File.dirname(plans_root))).to be(false)
    end
  end

  describe ".ensure_ignored! and the plan lock" do
    it "makes git ignore a plan's lock file, even where the state file was ignored already" do
      Dir.mktmpdir do |root|
        system("git", "-C", root, "init", "-q")
        File.write(File.join(root, ".gitignore"), "#{described_class::IGNORE.first}\n")

        expect(described_class.ensure_ignored!(root)).to be(true)
        expect(system("git", "-C", root, "check-ignore", "-q", ".plans/001.00━━⚪━━❯x/locked-by.pid")).to be(true)
        expect(described_class.ensure_ignored!(root)).to be(false)
      end
    end
  end
end
