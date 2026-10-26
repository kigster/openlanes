# frozen_string_literal: true

require "json"
require "open3"

# Plan 021.00 end to end: locks and the run's state file live in the runtime
# state directory, so `.plans/` holds only what is committed. A real tree in
# a real git repository, the real `exe/openlanes` in a subprocess; nothing
# stubbed but `XDG_STATE_HOME`, which spec_helper points at a temp directory.
RSpec.describe "runtime state outside .plans", :tree do
  let(:exe) { File.expand_path("../../exe/openlanes", __dir__) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:state_dir) { OpenLanes::Runtime.dir(root: repo_root) }

  def openlanes(*)
    out, err, status = Open3.capture3({ "NO_COLOR" => "1" }, exe, *, chdir: repo_root)
    [out, err, status.exitstatus]
  end

  def folder(ordinal) = Dir.glob(File.join(plans_root, "#{ordinal}*")).first

  def legacy_lock(ordinal, pid:, host: Socket.gethostname)
    File.write(File.join(folder(ordinal), OpenLanes::Plans::Lock::FILENAME),
      JSON.generate("pid" => pid, "host" => host, "started_at" => "2026-10-13T09:00:00Z"))
  end

  def dead_pid = Process.spawn("true").tap { Process.wait(it) }

  before do
    init_repo
    plans do |t|
      t.plan "001.00", :new, "locked", files: { "spec.md" => spec_body }
      t.plan "002.00", :new, "legacy-dead", files: { "spec.md" => spec_body }
      t.plan "003.00", :new, "legacy-foreign", files: { "spec.md" => spec_body }
    end
    commit_all("plans")
  end

  context "with a lock taken and a run saved" do
    let(:locks) { OpenLanes::Engine::PlanLocks.new }

    before do
      locks.hold("001.00", folder("001.00"))
      state = OpenLanes::Engine.state_file(tree)
      state.begin_run!(root: repo_root)
      state.record("001.00", agent: "backend-coder", round: 1, status: "Started")
      state.save
    end

    after { locks.release("001.00") }

    it "writes nothing under .plans, and both files into the state directory" do
      status = repo_git("status", "--porcelain", "--ignored")

      aggregate_failures do
        expect(status.lines.grep(/\.plans/)).to eq([])
        expect(File).to exist(File.join(state_dir, "openlanes-state.json"))
        expect(File).to exist(File.join(state_dir, "locks", "001.00.lock"))
      end
    end

    it "still sees the lock after the folder is renamed, in Lock.read, the reporter and the snapshot" do
      renamed = folder("001.00").sub("⚪", "⭐")
      File.rename(folder("001.00"), renamed)
      listed, = openlanes("plans")

      aggregate_failures do
        expect(OpenLanes::Plans::Lock.read(renamed)&.pid).to eq(Process.pid)
        expect(listed).to include("🔑 Locked")
        expect(snapshot_plan("001.00")[:locked]).to include(pid: Process.pid, foreign: false)
      end
    end
  end

  it "clears a legacy lock a dead local pid left, and keeps and reports a foreign one" do
    legacy_lock("002.00", pid: dead_pid)
    legacy_lock("003.00", pid: 1, host: "elsewhere.invalid")
    openlanes("resync", "dirs")
    listed, = openlanes("plans")

    aggregate_failures do
      expect(File).not_to exist(File.join(folder("002.00"), OpenLanes::Plans::Lock::FILENAME))
      expect(OpenLanes::Plans::Lock.read(folder("003.00"))).to be_foreign
      expect(listed).to include("held on elsewhere.invalid")
      expect(snapshot_plan("003.00")[:locked]).to include(host: "elsewhere.invalid", foreign: true)
    end
  end

  it "resumes an interrupted run from a legacy .plans/openlanes-state.json, and leaves it there" do
    legacy = File.join(plans_root, OpenLanes::Engine::StateFile::FILENAME)
    File.write(legacy,
      JSON.generate("run" => { "pid" => dead_pid },
        "plans" => { "001.00" => { "stages" => [{ "agent" => "backend-coder", "round" => 1, "status" => "Started" }] } }))

    stranded = OpenLanes::Engine.state_file(tree).load.stranded

    aggregate_failures do
      expect(stranded.map(&:first)).to eq(["001.00"])
      expect(File).to exist(legacy)
    end
  end

  # @param ordinal [String]
  # @return [Hash] that plan's entry in the live snapshot, read as the page reads it
  def snapshot_plan(ordinal)
    node = OpenLanes::Live::Node.new(id: "3f9a0c7be21d44a8f6031c5d",
      user: "dana",
      host: "studio-mini",
      ip: "10.0.4.12",
      checkout: "~/github/example/openlanes",
      checkout_id: "a1b2c3d4e5f6")
    keys = OpenLanes::Live::Keys.new(repo: "github.com/example/openlanes", node: node.name)
    board = OpenLanes::Engine::Board.new(started_at: 0,
      status: :running,
      plans: [ordinal],
      up: 0,
      down: 0,
      rows: [],
      root: repo_root,
      running: 0,
      live_up: 0,
      live_down: 0)
    snapshot = OpenLanes::Live::Snapshot.new(board:,
      tree: OpenLanes::Plans::Tree.new(dir: plans_root),
      agents: OpenLanes::Agents::Registry.new,
      node:,
      repo: keys.repo,
      project: "example",
      seq: 1,
      claims: OpenLanes::Live::Claims.new(store: OpenLanes::Live.memory_store, keys:))
    JSON.parse(JSON.generate(snapshot.to_h), symbolize_names: true)[:plans].find { it[:ordinal] == ordinal }
  end
end
