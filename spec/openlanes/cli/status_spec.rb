# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::Status, :tree do
  subject(:command) { described_class.new }

  let(:pid_dir) { Dir.mktmpdir("pids") }
  let(:dir) { OpenLanes::Supervision::PidDir.new(pid_dir) }
  let(:live) { [] }
  let(:probe) { instance_double(OpenLanes::Supervision::Probe) }
  let(:started) { (Time.now - 7200).strftime("%a %b %e %H:%M:%S %Y") }

  def file(role, pid, **) = OpenLanes::Supervision::PidFile.new(role:, pid:, started:, root: Dir.pwd, **)

  def status = strip_ansi(CapturedStream.capture { command.call(dir: plans_root) }.first)

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
    allow(OpenLanes::Supervision).to receive(:probe).and_return(probe)
  end

  context "with nothing running and no plans" do
    it { expect(status).to eq("No factory process is running in #{Dir.pwd}.\nNo plans in #{plans_root}.\n") }
  end

  context "with a factory up" do
    let(:live) { [10, 11] }

    before do
      dir.write(file("supervisor", 10, url: "http://127.0.0.1:11000", failed: { "web" => "3 crashes in 5m" }))
      dir.write(file("engine", 11))
    end

    it("shows the supervisor up, with its URL and what it gave up on") do
      expect(status).to match(%r{supervisor\s+│\s+10\s+│\s+up\s+│\s+2h\s+│\s+http://127.0.0.1:11000; web given up: 3 crashes in 5m})
    end

    it("shows the engine up") { expect(status).to match(/engine\s+│\s+11\s+│\s+up/) }
  end

  context "with a crashed process" do
    before { dir.write(file("web", 12)) }

    it("says it crashed, with no uptime") { expect(status).to match(/web\s+│\s+12\s+│\s+crashed\s+│\s+│/) }
  end

  context "with a run" do
    let(:live) { [20] }

    before { dir.write(file("run", 20, plans: %w[005 006])) }

    it("names its plans") { expect(status).to match(/run 005,006\s+│\s+20\s+│\s+up/) }
  end

  context "with an unreadable file" do
    before do
      FileUtils.mkdir_p(pid_dir)
      File.write(File.join(pid_dir, "engine.pid"), "")
    end

    it { expect(status).to include("unreadable") }
  end

  context "with plans" do
    before do
      plans do |t|
        t.plan "001.00", :building, "one"
        t.plan "002.00", :building, "two"
      end
    end

    it("counts them by state") { expect(status).to match(/🔨?.*Building\s+│\s+2/) }
  end
end
