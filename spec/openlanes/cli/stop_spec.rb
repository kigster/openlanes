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
    out, err, = CapturedStream.capture { command.call(dry_run: false, all: false, **) }
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

  context "with --dry-run over a stale file" do
    before { dir.write(file("engine", 11)) }

    it("says it would remove it") { expect(stop(dry_run: true).first).to match(/not running: stale PID file\s+│/) }
  end
end
