# frozen_string_literal: true

# `openlanes web`: the API server on its own. Puma, the browser and the
# demo's thread are replaced at their seams; what is under test is which
# store, which keys and which words.
RSpec.describe OpenLanes::CLI::Web, :tree do
  subject(:command) { described_class.new }

  let(:store) { OpenLanes::Live.memory_store }
  let(:server) { instance_double(OpenLanes::Web::Server, start: nil, url: "http://127.0.0.1:11000", wait: nil, stop: nil) }
  let(:demo) { instance_double(OpenLanes::Web::Demo, stop: nil) }
  let(:built) { {} }
  let(:traps) { {} }
  let(:result) { run }
  let(:stderr) { unwrapped(result[1]) }

  before do
    plans { |t| t.plan("001.00", :new, "first", files: { "spec.md" => "# Spec" }) }
    allow(OpenLanes::Live).to receive_messages(connect: store, store:)
    allow(OpenLanes::Web).to receive(:server) do |**keywords|
      built[:server] = keywords
      allow(server).to receive_messages(listen: keywords[:listen],
        port: 11_000,
        urls: keywords[:listen].urls(11_000, addresses: %w[127.0.0.1 192.168.1.20]))
      server
    end
    allow(OpenLanes::Web).to receive(:demo) do |**keywords|
      built[:demo] = keywords
      allow(demo).to receive(:start).and_return(demo)
      demo
    end
    allow(OpenLanes::Web).to receive(:open)
    allow(Signal).to receive(:trap) { |name, &block| traps[name] = block }
  end

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(dir: plans_root, port: "11000", open: true, demo: false, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  it "serves until stopped and says where" do
    expect(stderr).to include("Control room: http://127.0.0.1:11000", "Redis: memory:// as")
  end

  describe "logging" do
    let(:default_log) { File.join(File.dirname(plans_root), "log", "development.log") }

    it "logs as web to log/development.log under the project" do
      result
      expect(File.read(default_log)).to match(%r{ I \[\d+:[^\]]+\] web -- listening -- \{url: "http://127\.0\.0\.1:11000"})
    end

    it "logs where the engine that spawned it said to, at its level and in its format" do
      handed = File.join(File.dirname(plans_root), "shared.log")
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENLANES_LOG").and_return(handed)
      allow(ENV).to receive(:[]).with("OPENLANES_LOG_FORMAT").and_return("json")
      result

      aggregate_failures do
        expect(OpenLanes::Log.settings).to have_attributes(file: handed, format: "json")
        expect(JSON.parse(File.read(handed))).to include("name" => "web", "message" => "listening")
        expect(File.exist?(default_log)).to be(false)
      end
    end

    it "refuses a level it does not know" do
      expect(run(log_level: "loud")).to match([anything, include("--log-level loud"), 64])
    end
  end

  it "listens on the port asked for" do
    result
    expect(built[:server][:port]).to eq("11000")
  end

  it "opens the page" do
    result
    expect(OpenLanes::Web).to have_received(:open).with("http://127.0.0.1:11000")
  end

  it "stops the server on INT and TERM" do
    result
    traps.fetch("TERM").call.join
    expect(server).to have_received(:stop)
  end

  it "answers the copilot with c3po-operator, in this server, on this checkout's keys" do
    result
    copilot = built[:server][:context].copilot
    expect([copilot, copilot.argv("x", nil).include?("--restricted")]).to match([be_a(OpenLanes::Live::Copilot::Operator), true])
  end

  it "stops c3po-operator on the way out" do
    operator = instance_double(OpenLanes::Live::Copilot::Operator, stop: nil)
    allow(OpenLanes::Live::Copilot::Operator).to receive(:new).and_return(operator)
    result
    expect(operator).to have_received(:stop)
  end

  it "says nothing with --quiet" do
    expect(unwrapped(run(quiet: true)[1])).not_to include("Control room")
  end

  context "with --no-open" do
    let(:result) { run(open: false) }

    it "leaves the browser alone" do
      result
      expect(OpenLanes::Web).not_to have_received(:open)
    end
  end

  context "with --redis-url" do
    let(:result) { run(redis_url: "redis://elsewhere:6380/4") }

    it "connects there" do
      result
      expect(OpenLanes::Live).to have_received(:connect).with("redis://elsewhere:6380/4")
    end
  end

  context "with OPENLANES_REDIS_URL, as `openlanes run` starts it" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENLANES_REDIS_URL").and_return("redis://:secret@run-host:6379/2")
    end

    it "connects to the run's Redis" do
      result
      expect(OpenLanes::Live).to have_received(:connect).with("redis://:secret@run-host:6379/2")
    end

    it "still lets --redis-url win" do
      run(redis_url: "redis://elsewhere:6380/4")
      expect(OpenLanes::Live).to have_received(:connect).with("redis://elsewhere:6380/4")
    end
  end

  context "with a blank OPENLANES_REDIS_URL" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENLANES_REDIS_URL").and_return("  ")
      allow(OpenLanes::Live).to receive(:redis_url).and_call_original
    end

    it "falls through to the usual lookup" do
      result
      expect(OpenLanes::Live).to have_received(:redis_url).with(option: nil, config: anything)
    end
  end

  context "without Redis" do
    before { allow(OpenLanes::Live).to receive(:connect).and_raise(OpenLanes::Live::Unavailable, "Redis at redis://h/0 did not answer PING") }

    it "refuses, and points at --demo" do
      expect([result[2], stderr]).to match([69, include("did not answer PING", "or try --demo")])
    end
  end

  context "when the port is taken" do
    before { allow(server).to receive(:start).and_raise(Errno::EADDRINUSE) }

    it "refuses and names the flag" do
      expect([result[2], stderr]).to match([69, include("Port 11000 is taken", "--port")])
    end
  end

  describe "where it listens" do
    it "is loopback unless told otherwise, and warns of nothing" do
      result
      expect([built[:server][:listen].ips, stderr]).to match([%w[127.0.0.1], satisfy { !it.include?("no login") }])
    end

    it "takes -p as --port" do
      expect(described_class.options.find { it.name == :port }.aliases).to eq(["-p"])
    end

    context "with --ips" do
      let(:result) { run(ips: "127.0.0.1, 192.168.1.20") }

      it "listens on each, and answers to them in the Host header" do
        result
        listen = built[:server][:listen]
        expect([listen.ips, built[:server][:context].listen]).to eq([%w[127.0.0.1 192.168.1.20], listen])
      end

      it "prints the other addresses and warns that the page has no login, even with --quiet" do
        quiet = unwrapped(run(ips: "192.168.1.20", quiet: true)[1])
        expect([stderr, quiet]).to match([include("Also on: http://192.168.1.20:11000", "no login"),
                                          include("Listening on 192.168.1.20", "no login")])
      end

      it "logs the warning" do
        result
        log = File.read(File.join(File.dirname(plans_root), "log", "development.log"))
        expect(log).to include("listening beyond loopback")
      end
    end

    context "with -I" do
      let(:result) { run(all_interfaces: true) }

      it "listens everywhere, and opens the page on loopback" do
        result
        expect([built[:server][:listen].ips, stderr]).to match([%w[0.0.0.0], include("Also on: http://192.168.1.20:11000")])
      end
    end

    it "refuses -I beside --ips" do
      expect(run(all_interfaces: true, ips: "127.0.0.1")).to match([anything, include("--ips or -I, not both"), 64])
    end

    it "refuses an address that is not one" do
      expect(run(ips: "127.0.0.1,nope")).to match([anything, include('--ips: "nope" is not an IP address'), 64])
    end

    context "when an address is not this machine's" do
      let(:result) { run(ips: "10.255.255.1") }

      before { allow(server).to receive(:start).and_raise(Errno::EADDRNOTAVAIL) }

      it "refuses and names the addresses" do
        expect([result[2], stderr]).to match([69, include("--ips 10.255.255.1", "not one of this machine's")])
      end
    end
  end

  context "with --identity but no --demo" do
    it "refuses: a live server answers only for this machine" do
      expect(run(identity: "demo@second-machine")).to match([anything, include("--identity is for the demo only"), 64])
    end
  end

  describe "--demo" do
    let(:result) { run(demo: true) }

    it "runs the demo engine on the server's store and keys" do
      result
      expect(built[:demo][:keys]).to eq(built[:server][:context].keys)
    end

    it "stops the demo engine after" do
      result
      expect(demo).to have_received(:stop)
    end

    it "keeps the demo's keys apart from a real run's" do
      result
      expect(built[:server][:context].keys.repo).to start_with("demo/")
    end

    it "answers the copilot with the demo's line, not with an agent" do
      result
      expect(built[:server][:context].copilot).to eq(OpenLanes::Web::Demo::COPILOT)
    end

    it "says it is the demo" do
      expect(stderr).to include("http://127.0.0.1:11000 (demo)")
    end

    it "publishes as this machine when no identity is declared" do
      result
      expect(built[:demo][:node]).to be_nil
    end

    context "with --identity" do
      let(:result) { run(demo: true, identity: "demo@second-machine") }
      let(:declared) { OpenLanes::Live::Node.declared("demo@second-machine", root: File.dirname(plans_root)) }

      it "is that machine to the board, the chat and the session" do
        result
        context = built[:server][:context]
        expect([context.node.label, context.keys.node, context.chat.machine, built[:demo][:node]])
          .to eq(["demo@second-machine", declared.name, declared.id, context.node])
      end

      it "says so" do
        expect(stderr).to include("as demo@second-machine (#{declared.name})")
      end

      it "refuses one that is not user@host" do
        expect(run(demo: true, identity: "second-machine")).to match([anything, include("--identity: an identity is user@host"), 64])
      end
    end

    context "without Redis" do
      before { allow(OpenLanes::Live).to receive(:connect).and_raise(OpenLanes::Live::Unavailable, "Redis at redis://h/0 did not answer PING") }

      it "keeps its board in memory and says so" do
        expect([result[2], stderr, built[:demo][:store]]).to match([0, include("in memory instead"), be_a(OpenLanes::Live::MemoryStore)])
      end
    end
  end
end
