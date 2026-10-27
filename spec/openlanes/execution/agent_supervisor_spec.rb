# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::AgentSupervisor do
  subject(:supervisor) { described_class.new(options, title: ->(text) { titles << text }, grace: 0.2) }

  let(:dir) { Dir.mktmpdir("agent-supervisor") }
  let(:root) { File.join(dir, "project") }
  let(:titles) { [] }
  let(:cli) { ["sh", "-c", "echo out; echo err >&2; exit 3"] }
  let(:options) do
    described_class::Options.new(root:,
      plan: "005.00",
      agent: "backend-coder",
      output: File.join(dir, "a.out"),
      status: File.join(dir, "a.status"),
      pid_file: pid_path,
      argv: cli)
  end
  let(:pid_path) { File.join(dir, "pids", "agent-005.00-backend-coder.pid") }
  let(:status) { JSON.parse(File.read(options.status)) }

  after { FileUtils.rm_rf(dir) }

  it("keeps the agent supervisor's grace equal to the child's") { expect(described_class::TERM_GRACE).to eq(OpenLanes::Execution::Child::TERM_GRACE) }

  context "with a CLI that exits" do
    let!(:code) { supervisor.call }

    it("ends with its status") { expect(code).to eq(3) }
    it("keeps its stdout and stderr in the output") { expect(File.read(options.output)).to eq("out\nerr\n") }
    it("writes its status") { expect(status).to eq("exitstatus" => 3) }
    it("removes its PID file") { expect(File).not_to exist(pid_path) }
    it("names itself for ps") { expect(titles).to eq(["openlanes-agent [project] 005.00 backend-coder"]) }
  end

  context "with the CLI still running" do
    # The CLI copies the PID file once it is there.
    let(:copy) { File.join(dir, "copy.json") }
    let(:cli) { ["sh", "-c", 'while [ ! -f "$0" ]; do sleep 0.01; done; cp "$0" "$1"', pid_path, copy] }
    let(:file) { OpenLanes::Supervision::PidFile.parse(File.read(copy)) }

    before { supervisor.call }

    it("writes a PID file every reader can parse") { expect(file).to have_attributes(role: "agent", pid: Process.pid, root:, plans: ["005.00"]) }
    it("records its start time for Probe") { expect(file.started).to match(/\A\w{3} \w{3} /) }
    it("names the CLI too") { expect(JSON.parse(File.read(copy))["child"]).to be_a(Integer) }
  end

  context "with a TERM handler already in place" do
    let(:handler) { proc {} }
    let!(:original) { Signal.trap("TERM", handler) }

    before { supervisor.call }
    after { Signal.trap("TERM", original) }

    it("puts it back once the CLI has ended") { expect(Signal.trap("TERM", original)).to be(handler) }
  end

  context "with a CLI killed by a signal" do
    let(:cli) { ["sh", "-c", "kill -9 $$"] }

    it("ends with 128 plus the signal") { expect(supervisor.call).to eq(137) }
    it("writes the signal") { supervisor.call && expect(status).to(eq("termsig" => 9)) }
  end

  context "with a CLI that cannot be started" do
    let(:cli) { [File.join(dir, "missing")] }
    let!(:code) { supervisor.call }

    it("ends with 127, as a shell does") { expect(code).to eq(127) }
    it("says why in the output") { expect(File.read(options.output)).to include("could not start") }
    it("writes no PID file") { expect(File).not_to exist(pid_path) }
  end

  context "when told to stop" do
    # The thread is handed the supervisor, and the supervisor reads no let:
    # a let read from that thread would wait on the memoization lock this
    # thread holds.
    subject(:supervisor) { described_class.new(options, title: ->(_) {}, grace: 0.2) }

    # A CLI that ignores TERM, so the grace runs out and KILL ends it.
    let(:cli) { ["sh", "-c", "trap '' TERM; echo up; while :; do sleep 0.05; done"] }
    let(:previous) { Signal.trap("TERM", "DEFAULT") }
    let(:code) do
      previous
      Thread.new(supervisor, &:call).tap do
        sleep(0.01) until File.exist?(pid_path)
        Process.kill("TERM", Process.pid)
      end.value
    end

    after { Signal.trap("TERM", previous) }

    it("TERMs the CLI's group, then KILLs it") { expect(code).to eq(137) }
  end

  it("spells INTERRUPT as the engine's control file does") { expect(described_class::INTERRUPT).to eq(OpenLanes::Execution::Control::INTERRUPT) }

  context "when told to pause" do
    subject(:supervisor) { described_class.new(options.with(control:), title: ->(_) {}, grace: 0.2) }

    let(:control) { File.join(dir, "control") }
    # A CLI that ends once its control file says INTERRUPT, as an agent
    # leaving its resume note would.
    let(:cli) { ["sh", "-c", "until grep -q INTERRUPT '#{control}' 2>/dev/null; do sleep 0.02; done; exit 5"] }
    let(:previous) { Signal.trap("USR1", "DEFAULT") }
    let(:code) do
      previous
      Thread.new(supervisor, &:call).tap do
        sleep(0.01) until File.exist?(pid_path)
        2.times { Process.kill("USR1", Process.pid) }
      end.value
    end

    after { Signal.trap("USR1", previous) }

    it("lets the CLI end of its own accord") { expect(code).to eq(5) }

    it "tells the control file INTERRUPT, once" do
      code
      expect(File.read(control)).to eq("INTERRUPT\n")
    end

    it "puts the USR1 handler back" do
      code
      expect(Signal.trap("USR1", "DEFAULT")).to eq("DEFAULT")
    end
  end

  context "when told to pause without a control file" do
    subject(:supervisor) { described_class.new(options, title: ->(_) {}, grace: 0.2) }

    let(:cli) { ["sh", "-c", "sleep 0.3; exit 6"] }
    let(:previous) { Signal.trap("USR1", "DEFAULT") }
    let(:code) do
      previous
      Thread.new(supervisor, &:call).tap do
        sleep(0.01) until File.exist?(pid_path)
        Process.kill("USR1", Process.pid)
      end.value
    end

    after { Signal.trap("USR1", previous) }

    it("runs the CLI on to its end") { expect(code).to eq(6) }

    it "writes no control file" do
      code
      expect(Dir.children(dir).grep(/control/)).to be_empty
    end
  end

  context "when its control file cannot be written" do
    subject(:supervisor) { described_class.new(options.with(control: File.join(dir, "missing", "control")), title: ->(_) {}, grace: 0.2) }

    let(:cli) { ["sh", "-c", "sleep 0.3; exit 7"] }
    let(:previous) { Signal.trap("USR1", "DEFAULT") }
    let(:code) do
      previous
      Thread.new(supervisor, &:call).tap do
        sleep(0.01) until File.exist?(pid_path)
        Process.kill("USR1", Process.pid)
      end.value
    end

    after { Signal.trap("USR1", previous) }

    it("runs the CLI on to its end") { expect(code).to eq(7) }
  end

  describe ".parse" do
    subject(:parsed) { described_class.parse(argv) }

    let(:required) { ["--root", root, "--plan", "005.00", "--agent", "a", "--output", "o", "--status", "s", "--pid-file", "p"] }

    context "with --control" do
      let(:argv) { [*required, "--control", "/tmp/c", "--", "true"] }

      it("reads the control file") { expect(parsed.control).to eq("/tmp/c") }
      it("keeps the CLI after --") { expect(parsed.argv).to eq(["true"]) }
    end

    context "without --control" do
      let(:argv) { [*required, "--", "true"] }

      it("has none") { expect(parsed.control).to be_nil }
    end
  end

  describe ".main" do
    context "with every flag" do
      let(:argv) do
        ["--root", root, "--plan", "005.00", "--agent", "a", "--output", options.output, "--status", options.status, "--pid-file", pid_path, "--", "true"]
      end

      it { expect(described_class.main(argv, title: ->(_) {})).to eq(0) }
    end

    context "with a flag missing" do
      it("refuses with 64") { expect { described_class.main(%w[--plan 005.00 -- true]) }.to output(/key not found: :root/).to_stderr }
    end

    context "without a command" do
      let(:argv) { ["--root", root, "--plan", "1", "--agent", "a", "--output", "o", "--status", "s", "--pid-file", "p"] }

      it("refuses with 64") { expect(described_class.main(argv)).to eq(64) }
    end
  end

  describe "libexec/openlanes-agent" do
    let(:script) { File.expand_path("../../../libexec/openlanes-agent", __dir__) }
    let(:args) do
      ["--root", root, "--plan", "005.00", "--agent", "backend-coder", "--output", options.output, "--status", options.status, "--pid-file", pid_path]
    end

    context "when run without rubygems" do
      before { system(RbConfig.ruby, "--disable-gems", script, *args, "--", "sh", "-c", "echo hi; exit 4") }

      it("runs the CLI") { expect(File.read(options.output)).to eq("hi\n") }
      it("ends with its status") { expect(status).to eq("exitstatus" => 4) }
    end

    context "when TERMed" do
      let(:pid) { Process.spawn(RbConfig.ruby, "--disable-gems", script, *args, "--", "sleep", "30") }

      before do
        pid
        sleep(0.01) until File.exist?(pid_path)
        Process.kill("TERM", pid)
        Process.wait(pid)
      end

      it("stops the CLI and records how") { expect(status).to eq("termsig" => 15) }
      it("removes its PID file") { expect(File).not_to exist(pid_path) }
    end
  end
end
