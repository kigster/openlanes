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

    context "without Redis" do
      before { allow(OpenLanes::Live).to receive(:connect).and_raise(OpenLanes::Live::Unavailable, "Redis at redis://h/0 did not answer PING") }

      it "keeps its board in memory and says so" do
        expect([result[2], stderr, built[:demo][:store]]).to match([0, include("in memory instead"), be_a(OpenLanes::Live::MemoryStore)])
      end
    end
  end
end
