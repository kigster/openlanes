# frozen_string_literal: true

# `openlanes start` is the supervisor (S1): it builds the engine and the web
# as programs and hands them to {OpenLanes::Supervision::Supervisor}, which
# every example here replaces, so nothing is spawned. The engine it starts
# is `openlanes engine`, whose own behavior engine_command_spec covers.
RSpec.describe OpenLanes::CLI::Start, :tree do
  subject(:command) { described_class.new }

  let(:pid_dir) { Dir.mktmpdir("pids") }
  let(:dir) { OpenLanes::Supervision::PidDir.new(pid_dir) }
  let(:handed) { {} }
  let(:seen) { [] }
  let(:supervisor) { instance_double(OpenLanes::Supervision::Supervisor, stop!: nil) }
  let(:exit_with) { 0 }
  let(:settled) { 11_000 }
  let(:web) do
    instance_double(OpenLanes::Web::Launcher,
      settle_port: settled,
      port:        11_000,
      url:         "http://127.0.0.1:11000",
      argv:        %w[openlanes web --port 11000],
      env:         { "OPENLANES_REDIS_URL" => "redis://x" },
      log:         "/tmp/web.log")
  end
  let(:spawner) { OpenLanes::Spawner::Fake.new(pids: [4242]) }
  let(:alive) { true }
  let(:host) { OpenLanes::Supervision::Host.new(spawner:, waiter: ->(_pid) { alive ? nil : :gone }, clock: OpenLanes::Clock::Fake.new) }
  let(:log) { File.join(Dir.pwd, "log", "openlanes-start.log") }

  let(:typed) { { dir: plans_root, isolation: "shared", web: true, open: true, background: false, quiet: false, port: "11000", rescan: "5" } }

  def start(**)
    out, err, status = CapturedStream.capture { command.call(**typed, **) }
    [strip_ansi(out), unwrapped(strip_ansi(err)), status || 0]
  end

  def engine_argv = handed.fetch(:programs).first.argv

  around do |example|
    saved = ENV.fetch("OPENLANES_PID_DIR")
    ENV["OPENLANES_PID_DIR"] = pid_dir
    example.run
  ensure
    ENV["OPENLANES_PID_DIR"] = saved
    FileUtils.rm_rf(pid_dir)
  end

  before do
    allow(OpenLanes::Supervision).to receive(:supervisor) do |**keywords|
      handed.merge!(keywords)
      supervisor
    end
    allow(supervisor).to receive(:call) do |&on_tick|
      handed[:on_tick] = on_tick
      seen << dir.read("supervisor")
      exit_with
    end
    allow(OpenLanes::Web).to receive(:launcher).and_return(web)
    allow(OpenLanes::Web).to receive(:open)
    allow(Signal).to receive(:trap)
    allow(OpenLanes::Supervision).to receive(:host).and_return(host)
  end

  describe "what it supervises" do
    let!(:result) { start(jobs: "3") }

    it("the engine, without its own page") do
      expect(engine_argv.first(3)).to eq([OpenLanes::Web::Launcher::EXE, "engine", "--no-web"])
    end

    it("hands the engine the flags typed") { expect(engine_argv).to include("--jobs=3", "--isolation=shared") }
    it("hands the engine none of the page's") { expect(engine_argv.drop(2).grep(/\A--(no-)?(port|open|web|ips|all-interfaces|admin-credentials)/)).to eq(["--no-web"]) }
    it("ends the factory with the engine") { expect(handed.fetch(:programs).first.essential).to be(true) }

    it("the page, as the launcher would start it") do
      expect(handed.fetch(:programs).last).to have_attributes(role: "web",
        argv: web.argv,
        env: web.env,
        options: include(%i[out err] => ["/tmp/web.log", "a"]))
    end

    it("writes its PID file with the page's URL while it supervises") { expect(seen.first).to have_attributes(pid: Process.pid, url: "http://127.0.0.1:11000") }
    it("removes it once it ends") { expect(dir.read("supervisor")).to be_nil }
    it("says where the page is") { expect(result[1]).to include("Factory supervisor: pid #{Process.pid}, control room at http://127.0.0.1:11000") }
    it("exits 0") { expect(result.last).to eq(0) }
  end

  context "when the engine ended the factory with a refusal" do
    let(:exit_with) { 69 }

    it("exits with its status") { expect(start.last).to eq(69) }
  end

  context "with --no-web" do
    before { start(web: false) }

    it("supervises the engine alone") { expect(handed.fetch(:programs).map(&:role)).to eq(["engine"]) }
    it("opens nothing") { expect(handed.fetch(:on_tick)).to be_nil }
  end

  context "with --no-open" do
    before { start(open: false) }

    it { expect(handed.fetch(:on_tick)).to be_nil }
  end

  describe "the browser" do
    before do
      start
      allow(OpenLanes::Web::Launcher).to receive(:answering?).and_return(false, true)
      3.times { handed.fetch(:on_tick).call(supervisor) }
    end

    it("opens once the page first answers, and only once") { expect(OpenLanes::Web).to have_received(:open).with("http://127.0.0.1:11000").once }
  end

  context "when a factory already runs here" do
    let(:probe) { instance_double(OpenLanes::Supervision::Probe, verified?: true) }
    let(:result) { start }

    before do
      allow(OpenLanes::Supervision).to receive(:probe).and_return(probe)
      dir.write(OpenLanes::Supervision::PidFile.new(role: "supervisor", pid: 777, started: "x", root: Dir.pwd, url: "http://127.0.0.1:11001"))
      result
    end

    it("refuses, with its URL") { expect([result.last, result[1]]).to match([75, include("already running here (pid 777) at http://127.0.0.1:11001")]) }
    it("starts nothing") { expect(handed).to be_empty }
  end

  context "when a crash left a supervisor's PID file" do
    before { dir.write(OpenLanes::Supervision::PidFile.new(role: "supervisor", pid: 777, started: "x", root: Dir.pwd)) }

    it("starts anyway") { expect(start.last).to eq(0) }
  end

  context "when every port is taken" do
    let(:settled) { nil }

    it("refuses") { expect(start.values_at(1, 2)).to match([include("are all taken"), 69]) }
  end

  describe "--background" do
    context "when the factory comes up" do
      before do
        dir.write(OpenLanes::Supervision::PidFile.new(role: "supervisor", pid: 4242, started: "x", root: Dir.pwd, url: "http://127.0.0.1:11000"))
        allow(OpenLanes::Web::Launcher).to receive(:answering?).with(11_000).and_return(true)
      end

      let!(:result) { start(background: true, all_interfaces: true, admin_credentials: "admin:s3cret") }

      it("prints the URL on STDOUT") { expect(result.first).to eq("http://127.0.0.1:11000\n") }
      it("says where its output goes") { expect(result[1]).to include("running in the background (pid 4242)", log) }
      it("starts this command again, detached") { expect(spawner.calls.first.argv.first(2)).to eq([OpenLanes::Web::Launcher::EXE, "start"]) }
      it("without --background") { expect(spawner.calls.first.argv.grep(/background/)).to be_empty }
      it("keeps the login out of argv") { expect(spawner.calls.first.argv.join(" ")).not_to include("s3cret") }
      it("hands it the login in the environment") { expect(spawner.calls.first.env).to include("OPENLANES_ADMIN_CREDENTIALS" => "admin:s3cret", "OPENLANES_DETACHED" => "1") }
      it("sends its output to the log") { expect(spawner.calls.first.options).to include(%i[out err] => [log, "a"], in: File::NULL) }
      it("supervises nothing itself") { expect(handed).to be_empty }
    end

    context "when the factory exits before it is up" do
      let(:alive) { false }

      before do
        FileUtils.mkdir_p(File.dirname(log))
        File.write(log, "Redis did not answer\n")
      end

      it("refuses with the end of its log") { expect(start(background: true).values_at(1, 2)).to match([include("did not start", "Redis did not answer"), 70]) }
    end

    context "when the factory never comes up" do
      it("refuses, pointing at status") { expect(start(background: true).values_at(1, 2)).to match([include("did not come up within 60s", "openlanes status"), 75]) }
    end
  end

  describe "a --background child" do
    before do
      ENV["OPENLANES_DETACHED"] = "1"
      allow(Process).to receive(:setsid)
      start
    end

    after { ENV.delete("OPENLANES_DETACHED") }

    it("leaves the terminal's session") { expect(Process).to have_received(:setsid) }
    it("hands nothing it starts the variable") { expect(ENV).not_to have_key("OPENLANES_DETACHED") }
  end

  it "is registered as start" do
    expect(OpenLanes::CLI.get(["start"]).command).to eq(described_class)
  end
end
