# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::Stop do
  subject(:command) { described_class.new }

  let(:pid_dir) { Dir.mktmpdir("pids") }
  let(:dir) { OpenLanes::Supervision::PidDir.new(pid_dir) }
  let(:live) { [] }
  let(:signals) { [] }
  let(:probe) { instance_double(OpenLanes::Supervision::Probe) }
  let(:signaller) { ->(signal, pid) { (signals << [signal, pid]) && live.delete(pid) } }

  def file(role, pid, **) = OpenLanes::Supervision::PidFile.new(role:, pid:, started: "x", root: Dir.pwd, **)

  def stop(**)
    out, err, = CapturedStream.capture { command.call(dry_run: false, all: false, web: false, **) }
    [strip_ansi(out), strip_ansi(err)]
  end

  around do |example|
    saved = ENV.fetch("OPENLANES_PID_DIR")
    ENV["OPENLANES_PID_DIR"] = pid_dir
    example.run
  ensure
    ENV["OPENLANES_PID_DIR"] = saved
    FileUtils.rm_rf(pid_dir)
  end

  before do
    allow(probe).to receive(:verified?) { live.include?(it.pid) }
    allow(OpenLanes::Supervision).to receive_messages(probe:,
      host: OpenLanes::Supervision::Host.new(signaller:, clock: OpenLanes::Clock::Fake.new))
  end

  context "with nothing running" do
    it("says so") { expect(stop.last).to include("Nothing is running in") }
  end

  context "with a factory" do
    let(:live) { [10] }

    before { dir.write(file("supervisor", 10)) }

    it("stops it") { expect(stop.first).to match(/supervisor\s+│\s+10\s+│\s+stopped/) }

    it "signals it" do
      stop
      expect(signals).to eq([["TERM", 10]])
    end
  end

  context "with a run and --all" do
    let(:live) { [20] }

    before { dir.write(file("run", 20, plans: %w[005 006])) }

    it("names the run by its plans") { expect(stop(all: true).first).to match(/run 005,006\s+│\s+20\s+│\s+stopped/) }
  end

  context "with a stale file" do
    before { dir.write(file("engine", 11)) }

    it("removes it and says so") { expect(stop.first).to include("not running: stale PID file removed") }
  end

  context "with --dry-run" do
    let(:live) { [10] }

    before { dir.write(file("supervisor", 10)) }

    it("says what it would stop") { expect(stop(dry_run: true).first).to include("would stop") }
    it("ends with the dry run footer") { expect(stop(dry_run: true).last).to include("1 process pending") }

    it "signals nothing" do
      stop(dry_run: true)
      expect(signals).to be_empty
    end
  end

  context "with a factory and --web" do
    let(:live) { [10, 11, 12] }

    before { [file("supervisor", 10), file("engine", 11), file("web", 12, url: "http://127.0.0.1:11000")].each { dir.write(it) } }

    it("stops the control room") { expect(stop(web: true).first).to match(/web\s+│\s+12\s+│\s+stopped/) }
    it("lists nothing else") { expect(stop(web: true).first).not_to match(/supervisor|engine/) }

    it "signals the control room alone" do
      stop(web: true)
      expect(signals).to eq([["TERM", 12]])
    end

    it "leaves the supervisor's and the engine's PID files" do
      stop(web: true)
      expect(dir.entries.map { it.file.role }).to eq(%w[supervisor engine])
    end

    it "previews under --dry-run, and signals nothing" do
      out, err = stop(web: true, dry_run: true)
      expect([out, err, signals]).to match([/web\s+│\s+12\s+│\s+would stop/, include("1 process pending"), []])
    end
  end

  context "with a factory whose control room is down and --web" do
    let(:live) { [10, 11] }

    before { [file("supervisor", 10), file("engine", 11)].each { dir.write(it) } }

    it("says no control room is running") { expect(stop(web: true).last).to include("No control room is running in") }

    it "signals nothing" do
      stop(web: true)
      expect(signals).to be_empty
    end
  end

  context "with a stale control room file and --web" do
    let(:live) { [11] }

    before { [file("engine", 11), file("web", 12)].each { dir.write(it) } }

    it("removes it and says so") { expect(stop(web: true).first).to match(/web\s+│\s+12\s+│\s+not running: stale PID file removed/) }
  end

  context "with --web and --all" do
    let(:live) { [10] }

    before { dir.write(file("supervisor", 10)) }

    it "refuses with exit 64, and signals nothing" do
      _out, err, status = CapturedStream.capture { command.call(dry_run: false, all: true, web: true) }
      expect([strip_ansi(err), status, signals]).to match([include("Pass --web or --all, not both"), 64, []])
    end
  end

  context "with -w on the command line" do
    let(:live) { [10, 12] }

    before { [file("supervisor", 10), file("web", 12)].each { dir.write(it) } }

    it "stops the control room alone" do
      CapturedStream.capture { Dry::CLI.new(OpenLanes::CLI).call(arguments: %w[stop -w]) }
      expect(signals).to eq([["TERM", 12]])
    end
  end

  context "with --dry-run over a stale file" do
    before { dir.write(file("engine", 11)) }

    it("says it would remove it") { expect(stop(dry_run: true).first).to match(/not running: stale PID file\s+│/) }
  end
end
