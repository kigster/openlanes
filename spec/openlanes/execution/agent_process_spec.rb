# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::AgentProcess do
  let(:dir) { Dir.mktmpdir("agent-process") }
  let(:root) { File.join(dir, "project") }
  let(:label) { described_class::Label.new(plan: "005.00", agent: "backend-coder") }
  let(:starter) { described_class.spawner(dir: File.join(dir, "traces"), root:) }
  let(:cli) { ["sh", "-c", "printf one; sleep 0.2; printf two; exit 3"] }
  let(:pid_file) { File.join(OpenLanes::Supervision.dir(root).path, "agent-005.00-backend-coder.pid") }

  after do
    described_class.live.each { it.terminate && it.wait }
    FileUtils.rm_rf(dir)
  end

  describe "an agent that runs to the end" do
    subject(:process) { starter.call(cli, chdir: dir, label:) }

    let(:read) { +"" }

    before { process.each_chunk { read << it } }

    it("reads all it wrote, as it arrived") { expect(read).to eq("onetwo") }
    it("ends with its status") { expect(process.wait).to have_attributes(exitstatus: 3, success?: false, signaled?: false) }
    it("is finished once waited for") { process.wait && expect(process).to(be_finished) }
    it("is no longer alive") { process.wait && expect(process).not_to(be_alive) }
    it("removes its files once read") { process.wait && expect(Dir.children(File.join(dir, "traces"))).to(be_empty) }
    it("is forgotten once waited for") { process.wait && expect(described_class.live).not_to(include(process)) }
  end

  describe "how it starts the agent supervisor" do
    let(:spawner) { OpenLanes::Spawner::Fake.new(pids: [4242]) }
    let(:starter) { described_class::Starter.new(dir: File.join(dir, "traces"), root:, spawner:) }
    let(:call) { spawner.calls.first }

    before do
      allow(described_class).to receive(:track) { it }
      starter.call(%w[claude -p hi], chdir: dir, env: { "A" => "1" }, label:)
    end

    it("runs the script without rubygems") { expect(call.argv.first(3)).to eq([RbConfig.ruby, "--disable-gems", described_class::SCRIPT]) }
    it("hands it the CLI after --") { expect(call.argv.last(4)).to eq(%w[-- claude -p hi]) }
    it("names the plan and the agent") { expect(call.argv.join(" ")).to include("--plan 005.00 --agent backend-coder") }
    it("in a group of its own, from the plan's checkout") { expect(call.options).to include(pgroup: true, chdir: dir, in: File::NULL, unsetenv_others: true) }
    it("with the adapter's environment") { expect(call.env).to include("A" => "1") }
    it("names no control file the label lacks") { expect(call.argv).not_to include("--control") }

    context "with a control file on the label" do
      let(:label) { described_class::Label.new(plan: "005.00", agent: "backend-coder", control: "/tmp/c") }

      it("hands it on, before the CLI") { expect(call.argv.join(" ")).to include("--control /tmp/c -- claude") }
    end
  end

  describe "#terminate" do
    subject(:process) { starter.call(["sh", "-c", "trap '' TERM; while :; do sleep 0.05; done"], chdir: dir, label:) }

    before do
      process
      sleep(0.01) until File.exist?(pid_file)
      process.terminate
    end

    it("leaves the agent supervisor to TERM, then KILL, the CLI") { expect(process.wait).to have_attributes(termsig: 9) }
    it("stops reading") { expect { |b| process.each_chunk(&b) }.not_to raise_error }
  end

  describe "#terminate on an agent supervisor that will not end" do
    subject(:process) do
      described_class.new(pid: supervisor,
        files: described_class::Files.new(output:, status: File.join(dir, "s"), pid_file: stub_pid_file),
        stop_within: 0.2)
    end

    # It says when its trap is set: a TERM sent before then ends it, and
    # the stop from here would never be needed.
    let(:ready) { File.join(dir, "ready") }
    let(:supervisor) { Process.spawn("sh", "-c", "trap '' TERM; : > \"$0\"; while :; do sleep 0.05; done", ready, pgroup: true) }
    let(:output) { File.join(dir, "o").tap { File.write(it, "") } }
    let(:cli) { Process.spawn("sleep", "30", pgroup: true) }
    let(:stub_pid_file) { File.join(dir, "agent.pid").tap { File.write(it, JSON.generate(child: cli)) } }
    let(:cli_status) { Process.wait2(cli).last }

    before do
      cli
      supervisor
      sleep(0.01) until File.exist?(ready)
      process.terminate
    end

    after do
      cli_status
      Process.kill("KILL", -supervisor)
    rescue Errno::ESRCH
      nil
    end

    it("KILLs it from here") { expect(process.wait).to eq(described_class::LOST) }
    it("KILLs the CLI's group") { expect(cli_status.termsig).to eq(9) }
    it("lets the reader go") { expect { |b| process.each_chunk(&b) }.not_to yield_control }
    it("only once") { expect { process.terminate }.not_to raise_error }
  end

  describe "an agent supervisor that died without a status" do
    subject(:process) do
      described_class.new(pid: Process.spawn("true"),
        files: described_class::Files.new(output: File.join(dir, "o").tap { File.write(it, "") }, status: File.join(dir, "s"), pid_file: File.join(dir, "p")))
    end

    it("ends the read") { expect { |b| process.each_chunk(&b) }.not_to yield_control }
    it("is lost") { expect(process.wait).to eq(described_class::LOST) }
  end

  describe ".terminate_all" do
    let(:process) { described_class.new(pid: 0, files: described_class::Files.new(output: "o", status: "s", pid_file: "p")) }

    before do
      allow(described_class).to receive(:live).and_return([process])
      # Stubbed too, so the suite's own cleanup does not wait out a stop.
      allow(process).to receive_messages(kill: nil, terminate: nil)
      described_class.terminate_all
    end

    it("TERMs every agent supervisor, which finishes the stop itself") { expect(process).to have_received(:kill).with("TERM") }
  end

  # An agent supervisor an earlier engine started (B1 in plan 041).
  describe ".attach" do
    subject(:taken) { described_class.attach(JSON.parse(JSON.generate(started.restart))) }

    let(:started) { starter.call(cli, chdir: dir, label:).tap { described_class.forget(it) && Process.detach(it.pid) } }
    let(:read) { +"" }

    before { taken.each_chunk { read << it } }

    it("reads what the agent wrote, from the start") { expect(read).to eq("onetwo") }
    it("ends with the status the agent left") { expect(taken.wait).to have_attributes(exitstatus: 3) }
    it("is tracked like one it started") { expect(described_class.live).to include(taken) }
    it("records what an engine needs to take it back") { expect(started.restart.keys).to eq(%i[pid output status pid_file]) }
  end

  describe "#kill" do
    subject(:process) { described_class.new(pid: Process.spawn("true").tap { Process.wait(it) }, files: described_class::Files.new(output: "o", status: "s", pid_file: "p")) }

    it("ignores one already gone") { expect(process.kill("TERM")).to be_nil }
  end

  describe "ExitStatus" do
    it("reads nothing from a missing file") { expect(described_class::ExitStatus.read(File.join(dir, "missing"))).to be_nil }
    it("is a success on exit 0") { expect(described_class::ExitStatus.new(exitstatus: 0, termsig: nil)).to be_success }
  end

  describe "Label" do
    it { expect(label.to_s).to eq("005.00-backend-coder") }
  end

  describe "the PID file" do
    let(:copy) { File.join(dir, "copy.json") }

    before do
      process = starter.call(["sh", "-c", 'while [ ! -f "$0" ]; do sleep 0.01; done; cp "$0" "$1"', pid_file, copy], chdir: dir, label:)
      process.each_chunk { nil }
      process.wait
    end

    it("lands where every other one does") { expect(JSON.parse(File.read(copy))).to include("role" => "agent", "agent" => "backend-coder") }
    it("is gone once the agent is") { expect(File).not_to exist(pid_file) }
  end
end
