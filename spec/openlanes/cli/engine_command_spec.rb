# frozen_string_literal: true

# `openlanes start` is `run` that stays: the same options and code, the
# control room required rather than hoped for, and an end that comes from
# Stop All Local or a signal, never from a fixed point, and not from every
# plan being finished either.
#
# Like run_spec, every example runs `--isolation shared` over a bare temp
# tree, publishes to a store in this process, and never spawns the server,
# a browser or an agent.
RSpec.describe OpenLanes::CLI::Start, :tree do
  subject(:command) { described_class.new }

  let(:live_store) { OpenLanes::Live.memory_store }
  let(:web) do
    instance_double(OpenLanes::Web::Launcher, ready?: true, port: 11_000, url: "http://127.0.0.1:11000", log: "/tmp/web.log", stop: nil)
  end
  let(:executor) { instance_double(OpenLanes::Execution::Executor) }

  # Between ticks, instead of sleeping a second. The default stops the run
  # the way a service manager does, with SIGTERM, once it has idled a while.
  let(:sleeper) do
    ticks = 0
    lambda { |_|
      ticks += 1
      Process.kill("TERM", Process.pid) if ticks == 3
      OpenLanes::Execution::Control.quit! if ticks > 5_000
      Thread.pass
    }
  end

  # STDERR as it was written, before strip_ansi: what a terminal received.
  let(:raw) { {} }

  before do
    allow(OpenLanes::Engine::Runner).to receive(:new).and_wrap_original do |original, **keywords|
      original.call(**keywords, sleeper:)
    end
    allow(OpenLanes::Live).to receive(:connect).and_return(live_store)
    allow(web).to receive(:start).and_return(web)
    allow(OpenLanes::Web).to receive(:launcher).and_return(web)
    allow(OpenLanes::Web).to receive(:open)
    allow(OpenLanes::Execution::Executor).to receive(:new).and_return(executor)
    allow(executor).to receive(:call)
  end

  after { OpenLanes::Execution::Control.reset! }

  def start(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = nil
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(dir: plans_root, isolation: "shared", log: File.join(plans_root, "..", "progress.log"), **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end
    raw[:err] = err.string
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  def asked
    plans do |t|
      t.plan "002.00", :blocked, "minesweeper", files: { "spec.md" => spec_body, "blocked.md" => "## B1 Board size\n\nHow big?\n" }
    end
  end

  def parse(*argv) = Dry::CLI::Parser.call(described_class, argv, "openlanes start")

  describe "its options" do
    it "takes run's, and --rescan" do
      expect(parse("-j", "4", "--port", "4848", "--no-open", "--rescan", "2").arguments)
        .to include(jobs: "4", port: "4848", open: false, rescan: "2")
    end

    it "leaves out --dry-run, which would publish no board" do
      expect(parse("--dry-run").error?).to be(true)
    end

    it "takes --plan, since it has no plans argument" do
      expect(parse("--plan", "005").arguments).to include(plan: "005")
    end

    it "takes no plans argument" do
      expect(described_class.arguments).to be_empty
    end

    # A factory that stops its plans part way is a run.
    it "leaves out --until" do
      expect(parse("--until", "planned").error?).to be(true)
    end

    it "is listed with the agents in help" do
      expect(OpenLanes::CLI.get(["start"]).command).to eq(described_class)
    end
  end

  describe "a plan blocked on a question" do
    before { asked }

    let!(:result) { start(open: false) }

    it "stays up past the fixed point until SIGTERM, then exits 0" do
      expect([result.last, result[1]]).to match([0, include("Stopped.", "Still waiting for answers: 002.00")])
    end

    it "idles rather than ends, and says on the terminal why" do
      expect(result[1]).to include("idle: waiting for answers on 002.00")
    end

    # The page is the board. The terminal gets each idle reason once per
    # change, as a plain line, however many ticks it idles for, and nothing
    # that moves the cursor or redraws a line.
    it "says the idle reason once, as a plain line, and never redraws" do
      aggregate_failures do
        expect(result[1].scan(/^\d\d:\d\d:\d\d  idle: waiting for answers on 002\.00$/).size).to eq(1)
        expect(raw[:err]).not_to match(/\r|\e\[/)
        expect(result[1]).not_to include("|        |")
      end
    end

    it "opens with one Info box: the log, the board and the control room" do
      aggregate_failures do
        expect(result[1].scan("─ Info ─").size).to eq(1)
        expect(result[1]).to include("Log:", "Live board:", "Control room: http://127.0.0.1:11000")
      end
    end

    it "opens its report with one blank line, not three, when no agent ran" do
      expect(result.first).to start_with("\n0 plans addressed")
    end

    it "runs the engine in stay mode, rescanning every five seconds" do
      expect(OpenLanes::Engine::Runner).to have_received(:new)
        .with(hash_including(stay: true, rescan: OpenLanes::Engine::Dispatcher::RESCAN))
    end

    # start is the command `run` points people at to watch their pull
    # requests, so its own staying must not drop the watch run builds.
    it "watches the pull requests a person merges" do
      expect(OpenLanes::Engine::Runner).to have_received(:new)
        .with(hash_including(watch: an_instance_of(OpenLanes::Engine::PrWatch)))
    end

    it "stops the control room" do
      expect(web).to have_received(:stop)
    end

    it "puts SIGTERM back the way it found it" do
      expect(Signal.trap("TERM", "DEFAULT")).to eq("DEFAULT")
    end
  end

  # Plan 009: a 💣 halts the engine, and the service idles on it rather
  # than ending, so the page stays up to answer it.
  describe "a 💣 others wait on" do
    before do
      path = nil
      plans do |t|
        path = t.plan "002.00", :blocked, "minesweeper", files: { "spec.md" => spec_body, "blocked.md" => "## B1 Board size\n" }
        t.plan "003.00",
          :building,
          "scoreboard",
          files: { "spec.md" => "---\ndepends_on: [\"002.00\"]\n---\n#{spec_body}", "plan.md" => "# P\n\n## U1\n" }
      end
      OpenLanes::Plans::PlanState.for(path).sign!(agent: "backend-coder", round: 1, status: "Blocked", at: Time.now - (8 * 86_400))
    end

    let!(:result) { start(open: false) }

    it "stays up and idle, says why, and exits 0 once stopped" do
      aggregate_failures do
        expect(result.last).to eq(0)
        expect(result[1]).to include("idle: halted by 💣 002.00")
        expect(executor).not_to have_received(:call)
      end
    end
  end

  describe "every plan finished" do
    before do
      plans { |t| t.plan "001.00", :deployed, "shipped", files: { "spec.md" => spec_body, "deployed.md" => "v1\n" } }
    end

    let!(:result) { start }

    it "stays up, waiting for the next plan, until SIGTERM" do
      expect([result.last, result[1]])
        .to match([0, include("idle: every plan is finished; create the next one from the page", "Stopped.")])
    end

    it "opens the control room on the idea dialog" do
      expect(OpenLanes::Web).to have_received(:open).with("http://127.0.0.1:11000#start")
    end
  end

  describe "no plans at all" do
    let!(:result) { start }

    it "starts anyway, and waits for the first plan from the page" do
      expect([result.last, result[1]])
        .to match([0, include("idle: no plans yet; create one from the page or with openlanes create", "Stopped.")])
    end

    it "opens the control room on the idea dialog" do
      expect(OpenLanes::Web).to have_received(:open).with("http://127.0.0.1:11000#start")
    end
  end

  describe "with work still to do" do
    before { asked }

    it "opens the board itself" do
      start
      expect(OpenLanes::Web).to have_received(:open).with("http://127.0.0.1:11000")
    end
  end

  describe "without Redis" do
    before do
      asked
      allow(OpenLanes::Live).to receive(:connect).and_raise(OpenLanes::Live::Unavailable, "Redis at redis://h/0 is unavailable")
    end

    let!(:result) { start }

    it "refuses with exit 69 instead of going headless" do
      expect([result.last, result[1]]).to match([69, include("Redis at redis://h/0 is unavailable", "openlanes start needs Redis")])
    end

    it "never starts the engine" do
      expect(OpenLanes::Engine::Runner).not_to have_received(:new)
    end
  end

  describe "when the control room does not answer" do
    before do
      asked
      allow(web).to receive(:ready?).and_return(false)
    end

    let!(:result) { start }

    it "refuses with exit 69, naming its log" do
      expect([result.last, result[1]]).to match([69, include("did not answer on http://127.0.0.1:11000", "/tmp/web.log")])
    end

    it "stops the server it started" do
      expect(web).to have_received(:stop)
    end
  end

  describe "the control room" do
    subject(:stderr) { unwrapped(result[1]) }

    before { asked }

    let(:result) { start(port: "4848") }

    it "starts on the store the board is published to, at the port asked for" do
      result
      expect(OpenLanes::Web).to have_received(:launcher).with(root: File.dirname(plans_root),
        plans_dir: plans_root,
        port: 4848,
        redis_url: "memory://",
        listen: OpenLanes::Web::Listen.parse(nil),
        credentials: nil)
    end

    it "names the port it asked for when the server had to move off it" do
      expect(stderr).to include("Control room: http://127.0.0.1:11000 (4848 was taken)")
    end

    context "with -I and a login" do
      let(:result) { start(open: false, all_interfaces: true, admin_credentials: "admin:s3cret") }

      it "hands the server the addresses and the login, and says it answers elsewhere behind it" do
        result
        aggregate_failures do
          expect(OpenLanes::Web).to have_received(:launcher)
            .with(hash_including(listen: OpenLanes::Web::Listen.parse("0.0.0.0"),
              credentials: OpenLanes::Web::AdminAuth.parse("admin:s3cret")))
          expect(stderr).to include("behind a login")
        end
      end
    end

    it "refuses -I without a login, before any agent starts" do
      expect(start(all_interfaces: true)).to match([anything, include("needs a login"), 64])
    end

    context "with --no-open" do
      let(:result) { start(open: false) }

      it "only prints the URL" do
        aggregate_failures do
          expect(stderr).to include("Control room: http://127.0.0.1:11000")
          expect(OpenLanes::Web).not_to have_received(:open)
        end
      end
    end
  end

  describe "--no-web, the page served apart" do
    before { asked }

    let!(:result) { start(web: false) }

    it "starts no server, and stays up for the page all the same" do
      aggregate_failures do
        expect(OpenLanes::Web).not_to have_received(:launcher)
        expect(OpenLanes::Engine::Runner).to have_received(:new).with(hash_including(stay: true))
        expect(unwrapped(result[1])).to include("The engine stays up for the control room `openlanes web` serves")
      end
    end
  end

  # O1 from the factory's side: a plan `openlanes run` holds is another
  # node's, stepped around rather than refused.
  describe "a plan a run holds" do
    before do
      asked
      plans { |t| t.plan "003.00", :building, "dice", files: { "spec.md" => spec_body, "plan.md" => "# Plan" } }
      OpenLanes::Live::Claims.new(store: live_store, keys: run_keys).claim(OpenLanes::Plans::Ordinal.parse("003"))
    end

    let(:root) { File.dirname(plans_root) }
    let(:run_keys) do
      OpenLanes::Live::Keys.new(repo: OpenLanes::Live::Repo.for(root), node: OpenLanes::Live::Node.current(root:, role: "run-1").name)
    end

    let!(:result) { start(open: false) }

    it "starts no agent on it, and stays up" do
      aggregate_failures do
        expect(executor).not_to have_received(:call)
        expect(result.last).to eq(0)
      end
    end
  end

  it "refuses a --rescan that is not a positive whole number" do
    asked
    expect(start(rescan: "soon").last).to eq(64)
  end
end
