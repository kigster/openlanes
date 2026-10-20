# frozen_string_literal: true

# `openlanes run`'s API server, as a process of its own. Spawned for real, but
# the executable is replaced by a tiny script so the suite starts no Puma.
RSpec.describe OpenLanes::Web::Launcher do
  subject(:launcher) do
    described_class.new(root: dir,
      plans_dir: File.join(dir, ".plans"),
      port:,
      redis_url: "redis://localhost:6379/9",
      log: File.join(dir, "web.log"),
      ready_within: 2,
      probe: -> { healthy })
  end

  let(:dir) { Dir.mktmpdir("launcher") }
  let(:port) { 4999 }
  let(:script) { File.join(dir, "fake-web") }
  let(:healthy) { true }

  before do
    File.write(script, "#!/bin/sh\necho \"$@\"\necho \"redis: $OPENLANES_REDIS_URL\"\ntrap 'exit 0' TERM\nwhile true; do sleep 0.05; done\n")
    File.chmod(0o755, script)
    stub_const("#{described_class}::EXE", script)
  end

  after do
    launcher.stop
    FileUtils.rm_rf(dir)
  end

  it "spawns `openlanes web` for this run's port and plans, never opening a browser" do
    expect(launcher.argv).to eq([script, "web", "--port", "4999", "--no-open", "--dir", File.join(dir, ".plans")])
  end

  it "keeps the Redis URL, and any password in it, off the command line" do
    expect(launcher.argv.join(" ")).not_to include("redis://")
  end

  it "hands the Redis URL to the server through its environment" do
    expect(launcher.env).to eq("OPENLANES_REDIS_URL" => "redis://localhost:6379/9")
  end

  describe "listening past loopback" do
    subject(:public_launcher) do
      described_class.new(root: dir,
        plans_dir: dir,
        port:,
        redis_url: "r",
        listen:      OpenLanes::Web::Listen.parse("0.0.0.0"),
        credentials: OpenLanes::Web::AdminAuth.parse("admin:s3cret"))
    end

    it "passes the addresses on the command line" do
      expect(public_launcher.argv.last(2)).to eq(["--ips", "0.0.0.0"])
    end

    it "hands the login over through the environment, never the command line" do
      expect([public_launcher.env, public_launcher.argv.join(" ")])
        .to match([include("OPENLANES_ADMIN_CREDENTIALS" => "admin:s3cret"), satisfy { !it.include?("s3cret") }])
    end

    it "still probes and opens the page on loopback, where no login is asked" do
      expect(public_launcher.url).to eq("http://127.0.0.1:#{port}")
    end
  end

  it "hands the engine's log settings to the server too, so both write one file" do
    logging = OpenLanes::Log::Settings.new(file: File.join(dir, "log", "development.log"), level: "debug", format: "json")
    launcher = described_class.new(root: dir, plans_dir: dir, port:, redis_url: "redis://localhost:6379/9", logging:)

    expect(launcher.env).to eq("OPENLANES_REDIS_URL" => "redis://localhost:6379/9",
      "OPENLANES_LOG" => logging.file,
      "OPENLANES_LOG_LEVEL" => "debug",
      "OPENLANES_LOG_FORMAT" => "json")
  end

  it "takes the settings this process logs with when given none" do
    settings = open_log(File.join(dir, "log", "development.log"))

    expect(described_class.new(root: dir, plans_dir: dir, port:, redis_url: "r").env).to include(settings.env)
  end

  it "points at loopback" do
    expect(launcher.url).to eq("http://127.0.0.1:4999")
  end

  context "when the server answers /healthz" do
    # The fake server's two lines, once both are written: a fixed sleep lost
    # that race on a loaded machine.
    let(:output) do
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      sleep 0.02 until File.read(launcher.log).include?("redis:") || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      File.read(launcher.log)
    end

    before { launcher.start }

    it "is ready, and logs the server's output" do
      expect([launcher.ready?, output]).to match([true, /\Aweb --port 4999/])
    end

    it "starts the server with the Redis URL in its environment" do
      expect(output).to include("redis: redis://localhost:6379/9")
    end

    it "stops its process group" do
      pid = launcher.pid
      launcher.stop
      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    end
  end

  context "when it never answers" do
    let(:healthy) { false }

    before do
      stub_const("#{described_class}::STOP_WITHIN", 0.2)
      File.write(script, "#!/bin/sh\ntrap '' TERM\nwhile true; do sleep 0.05; done\n")
      launcher.start
    end

    it "is not ready, and is killed when TERM is ignored" do
      launcher.stop
      expect([launcher.ready?, launcher.pid]).to eq([false, nil])
    end

    describe "after KILL" do
      let(:pid) { launcher.pid }

      before do
        allow(Process).to receive(:waitpid).and_call_original
        pid
        launcher.stop
      end

      it "reaps the server, leaving no zombie behind" do
        expect { Process.waitpid(pid, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
      end

      it "waits for the reap rather than polling once" do
        expect(Process).to have_received(:waitpid).with(pid).once
      end
    end
  end

  context "when it dies at once" do
    let(:healthy) { false }

    before do
      File.write(script, "#!/bin/sh\nexit 3\n")
      launcher.start
    end

    it "gives up without waiting out the deadline" do
      expect(launcher.ready?).to be(false)
    end
  end

  context "when the port asked for is taken" do
    # Another `openlanes web` answering /healthz there must not pass for ours.
    let(:squatter) { TCPServer.new(OpenLanes::Web::HOST, 0) }
    let(:port) { squatter.addr[1] }

    before { launcher.start }

    after { squatter.close }

    it "moves to the next free port, before spawning anything" do
      expect([launcher.port, launcher.argv[3], launcher.url]).to eq([port + 1, (port + 1).to_s, "http://127.0.0.1:#{port + 1}"])
    end
  end

  context "when every port tried is taken" do
    let(:squatter) { TCPServer.new(OpenLanes::Web::HOST, 0) }
    let(:port) { squatter.addr[1] }

    before do
      stub_const("#{described_class}::PORTS_TRIED", 1)
      launcher.start
    end

    after { squatter.close }

    it "spawns nothing, is not ready, and says why in its log" do
      expect([launcher.pid, launcher.ready?, File.read(launcher.log)]).to match([nil, false, /Ports #{port}-#{port} are all taken/])
    end
  end

  describe "#healthy?, against nothing listening" do
    subject(:probe) { described_class.new(root: dir, plans_dir: dir, port: 1, redis_url: "x") }

    it "is false" do
      expect(probe.send(:healthy?)).to be(false)
    end
  end

  it "keeps its log in the temp dir by default" do
    expect(described_class.new(root: "/work/widgets", plans_dir: "/p", port: 1, redis_url: "x").log)
      .to eq(OpenLanes::Engine::ProgressLog.default_path("/work/widgets", kind: "web"))
  end
end
