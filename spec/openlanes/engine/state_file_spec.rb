# frozen_string_literal: true

require "json"

RSpec.describe OpenLanes::Engine::StateFile, :tree do
  subject(:state) { described_class.new(path:, pid: 4242) }

  let(:path) { File.join(plans_root, described_class::FILENAME) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }

  it "lives in the runtime state directory, not in .plans" do
    expect(described_class.for(tree)).to eq(OpenLanes::Runtime.state_file(root: File.dirname(plans_root)))
  end

  it "leaves no openlanes-state.json under .plans after a save" do
    saved = described_class.new(path: described_class.for(tree), legacy: described_class.legacy_for(tree))
    saved.begin_run!(root: "/repo")
    saved.save
    expect(Dir.glob(File.join(plans_root, "**", "openlanes-state.json*"))).to be_empty
  end

  it "records the host, and never calls a run on another host dead" do
    dead = described_class.new(path:, pid: 999_999_999)
    dead.begin_run!(root: "/repo")
    dead.record("001.00", agent: "spec-writer", round: 1, status: "Started")
    dead.save
    allow(Socket).to receive(:gethostname).and_return("elsewhere.invalid")

    fresh = described_class.new(path:, pid: 4242).load
    aggregate_failures do
      expect(JSON.parse(File.read(path)).dig("run", "host")).not_to eq("elsewhere.invalid")
      expect(fresh).not_to be_previous_run_dead
      expect(fresh.stranded).to be_empty
    end
  end

  it "starts empty, saves atomically, and loads what it saved" do
    state.begin_run!(root: "/repo")
    state.record("001.00", agent: "researcher", round: 1, status: "Started", model: "haiku")
    state.save
    loaded = described_class.new(path:, pid: 4242).load
    aggregate_failures do
      expect(loaded.stages("001.00").first).to include("agent" => "researcher", "status" => "Started", "model" => "haiku")
      expect(JSON.parse(File.read(path)).dig("run", "pid")).to eq(4242)
      expect(Dir.children(plans_root).grep(/\.tmp\z/)).to be_empty
    end
  end

  it "keeps the live run's record beside the stages, and loads it back" do
    state.live = { "seq" => 3, "held_cars" => ["001.00/backend-coder"] }
    state.save
    expect(described_class.new(path:, pid: 4242).load.live).to eq("seq" => 3, "held_cars" => ["001.00/backend-coder"])
  end

  it "merges later fields into the same stage rather than adding a second one" do
    state.record("001.00", agent: "researcher", round: 1, status: "Started")
    state.record("001.00", agent: "researcher", round: 1, status: "Completed", up: 12)
    expect(state.stages("001.00").size).to eq(1)
    expect(state.stages("001.00").first).to include("status" => "Completed", "up" => 12)
  end

  it "keeps a second round as its own stage" do
    state.record("001.00", agent: "researcher", round: 1, status: "Interrupted")
    state.record("001.00", agent: "researcher", round: 2, status: "Started")
    expect(state.stages("001.00").map { |s| s["round"] }).to eq([1, 2])
  end

  # A harness that died leaves Started stages behind; the next one must
  # know they are stranded rather than still running.
  it "reports stages a dead run left Started as stranded" do
    dead = described_class.new(path:, pid: 999_999_999)
    dead.begin_run!(root: "/repo")
    dead.record("001.00", agent: "spec-writer", round: 1, status: "Started")
    dead.record("002.00", agent: "researcher", round: 1, status: "Completed")
    dead.save

    fresh = described_class.new(path:, pid: 4242).load
    aggregate_failures do
      expect(fresh).to be_previous_run_dead
      expect(fresh.stranded.map { |ordinal, stage| [ordinal, stage["agent"]] }).to eq([["001.00", "spec-writer"]])
    end
  end

  it "does not call a live run's Started stages stranded" do
    state.begin_run!(root: "/repo")
    state.record("001.00", agent: "spec-writer", round: 1, status: "Started")
    state.save
    fresh = described_class.new(path:, pid: 4242).load
    expect(fresh.stranded).to be_empty
  end

  # B5 in plan 041: what a restarted engine needs, saved at once.
  describe "#restart" do
    let(:stage) { described_class.new(path:, pid: 4242).load.stages("001.00").first }

    before do
      state.record("001.00", agent: "researcher", round: 1, status: "Started")
      state.restart("001.00", agent: "researcher", round: 1, process: { pid: 7 }, cwd: "/repo")
      state.restart("001.00", agent: "researcher", round: 1, deadline: "2026-10-27T00:00:00Z")
      state.restart("002.00", agent: "researcher", round: 1, cwd: "/nowhere")
    end

    it("merges each field into the stage, as JSON reads it back") do
      expect(stage["restart"]).to eq("process" => { "pid" => 7 }, "cwd" => "/repo", "deadline" => "2026-10-27T00:00:00Z")
    end

    it("records nothing for a stage it does not have") { expect(described_class.new(path:, pid: 4242).load.stages("002.00")).to be_empty }
  end

  # The file moved up out of `tmp/` after runs had already written there.
  # One that died under the old layout still has to be picked up, or its
  # Started stages are invisible and it silently restarts from zero.
  describe "the file a run left in the old tmp/ directory" do
    subject(:loaded) { described_class.new(path:, pid: 4242, legacy: described_class.legacy_for(tree)).load }

    let(:path) { described_class.for(tree) }
    let(:legacy) { described_class.legacy_for(tree).last }
    let(:stage) { { "agent" => "spec-writer", "round" => 1, "status" => "Started" } }
    let(:written) { { "run" => { "pid" => 999_999_999 }, "plans" => { "001.00" => { "stages" => [stage] } } } }

    before do
      FileUtils.mkdir_p(File.dirname(legacy))
      File.write(legacy, JSON.generate(written))
    end

    it "is read when the current path holds nothing" do
      expect(loaded.stages("001.00").first).to include("agent" => "spec-writer")
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

  describe "the file a run left in .plans itself" do
    subject(:loaded) { described_class.new(path: described_class.for(tree), pid: 4242, legacy: described_class.legacy_for(tree)).load }

    let(:legacy) { described_class.legacy_for(tree).first }

    before do
      File.write(legacy,
        JSON.generate({ "run" => { "pid" => 999_999_999 },
                                                 "plans" => { "003.00" => { "stages" => [{ "agent" => "a", "round" => 1, "status" => "Started" }] } } }))
    end

    it "is read, reported stranded, and left on disk" do
      aggregate_failures do
        expect(loaded.stranded.map(&:first)).to eq(["003.00"])
        expect(File.file?(legacy)).to be(true)
      end
    end
  end

  describe ".ensure_ignored!" do
    subject(:root) { File.dirname(plans_root) }

    it "adds the temp-file line to .gitignore once, and says so" do
      system("git", "-C", root, "init", "-q")
      aggregate_failures do
        expect(described_class.ensure_ignored!(root)).to be(true)
        expect(File.read(File.join(root, ".gitignore"))).to include(".plans/**/*.tmp\n")
        expect(described_class.ensure_ignored!(root)).to be(false)
      end
    end

    it "makes git ignore the temp siblings plan documents are written through" do
      system("git", "-C", root, "init", "-q")
      described_class.ensure_ignored!(root)
      %w[state.json.1.2.tmp blocked.md.1.tmp].each do |name|
        expect(system("git", "-C", root, "check-ignore", "-q", ".plans/001.00━━⚪━━❯x/#{name}")).to be(true)
      end
    end

    it "leaves unrelated content and legacy lines alone, appending only its block" do
      system("git", "-C", root, "init", "-q")
      before = "/node_modules\n.plans/openlanes-state.json\nlocked-by.pid\n"
      File.write(File.join(root, ".gitignore"), before)
      described_class.ensure_ignored!(root)
      expect(File.read(File.join(root, ".gitignore"))).to eq("#{before}.plans/**/*.tmp\n")
    end

    it "matches the repository's own .gitignore too" do
      repo = File.expand_path("../../..", __dir__)
      %w[state.json.1.2.tmp blocked.md.1.tmp].each do |name|
        expect(system("git", "-C", repo, "check-ignore", "-q", "--no-index", ".plans/001.00━━⚪━━❯x/#{name}")).to be(true)
      end
    end

    it "does nothing outside a repository" do
      expect(described_class.ensure_ignored!(File.dirname(plans_root))).to be(false)
    end
  end
end
