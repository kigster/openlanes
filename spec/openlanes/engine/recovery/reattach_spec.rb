# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Recovery::Reattach, :tree do
  subject(:found) { described_class.new(runner:, state: OpenLanes::Engine::StateFile.new(path: state_path), probe:).call }

  let(:agent) { instance_double(OpenLanes::Agents::Agent, name: "backend-coder") }
  let(:agents) { instance_double(OpenLanes::Agents::Registry) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:runner) { instance_double(OpenLanes::Engine::Runner, tree:, agents:, foreign?: foreign) }
  let(:foreign) { false }
  let(:dir) { Dir.mktmpdir("reattach") }
  let(:state_path) { File.join(dir, "state.json") }
  let(:pid_file) { File.join(dir, "agent-003.00-backend-coder.pid") }
  let(:status_file) { File.join(dir, "agent.status") }
  let(:dead_pid) { Process.spawn("true").tap { Process.wait(it) } }
  let(:probe) { instance_double(OpenLanes::Supervision::Probe, verified?: verified) }
  let(:verified) { true }
  let(:recorded_pid) { 4242 }
  let(:written_pid) { 4242 }
  let(:restart) do
    { process: { pid: recorded_pid, output: File.join(dir, "agent.out"), status: status_file, pid_file: },
      cwd: dir, trace: "t", control: "c", before: { head: nil, remotes: {}, reflogs: {} }, deadline: "2026-10-27T00:00:00Z" }
  end

  def dead_run(**fields)
    state = OpenLanes::Engine::StateFile.new(path: state_path, pid: dead_pid)
    state.begin_run!(root: dir)
    state.record("003.00", agent: "backend-coder", round: 2, status: "Started", state: "building")
    state.restart("003.00", agent: "backend-coder", round: 2, **fields)
  end

  before do
    plans { |t| t.plan "003.00", :building, "work" }
    allow(agents).to receive(:find).with("backend-coder").and_return(agent)
    File.write(pid_file, JSON.generate(role: "agent", pid: written_pid, started: "x", root: dir))
    dead_run(**restart)
  end

  after { FileUtils.rm_rf(dir) }

  context "with the agent still running" do
    it("finds it") { expect(found.map { [it.key, it.agent, it.from] }).to eq([[["003.00", "backend-coder", 2], agent, :building]]) }
    it("carries what was recorded") { expect(found.first.restart).to include("cwd" => dir, "trace" => "t") }
  end

  context "with a pid file that names another process" do
    let(:written_pid) { 4343 }

    it { is_expected.to be_empty }
  end

  context "with a process the probe does not recognise" do
    let(:verified) { false }

    it { is_expected.to be_empty }

    context "when it ended and left its status" do
      before { File.write(status_file, "0\n") }

      it("finds it") { expect(found.size).to eq(1) }
    end
  end

  context "with no pid file" do
    before { File.delete(pid_file) }

    it { is_expected.to be_empty }
  end

  context "with a context recorded only in part" do
    let(:restart) { { process: { pid: 4242, pid_file: } } }

    it { is_expected.to be_empty }
  end

  context "with a plan another machine holds" do
    let(:foreign) { true }

    it { is_expected.to be_empty }
  end

  context "with an agent no longer defined" do
    before { allow(agents).to receive(:find).and_return(nil) }

    it { is_expected.to be_empty }
  end

  context "with a plan no longer there" do
    before { FileUtils.rm_rf(tree.find("003.00").feature.path) }

    it { is_expected.to be_empty }
  end
end
