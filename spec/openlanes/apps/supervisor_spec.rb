# frozen_string_literal: true

require "rbconfig"
require "socket"

# Real processes on real ports: the fixture server is a few lines of Ruby
# started through `sh -c`, exactly as an app's `start:` line is.
RSpec.describe OpenLanes::Apps::Supervisor do
  let(:dir) { File.realpath(Dir.mktmpdir("openlanes-supervisor")) }
  let(:registry) { OpenLanes::Apps::Ports.new(path: File.join(dir, "ports.json")) }
  let(:published) { [] }
  let(:server) { File.expand_path("../../fixtures/apps/servers/server.rb", __dir__) }
  let(:ready_timeout) { 10 }
  let(:supervisor) do
    described_class.new(definition:,
      root: dir,
      plan: "012.00",
      branch: "kig/012.00-app",
      registry:,
      publisher: ->(status) { published << status },
      ready_timeout:,
      poll: 0.05)
  end
  # Child keeps one list for the whole process, so other examples' children
  # are in it too; only the ones this example started count.
  let!(:children_before) { OpenLanes::Execution::Child.live }

  after do
    supervisor.stop
    FileUtils.rm_rf(dir)
  end

  def run_line(name, *flags) = "#{RbConfig.ruby} #{server} --name #{name} --port-env PORT_#{name.upcase} #{flags.join(" ")}"

  def app(*processes) = OpenLanes::Apps::Definition.new(kind: "web", processes:)

  def process(name, *flags, **) = OpenLanes::Apps::ProcessSpec.new(name:, start: run_line(name, *flags), **)

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def connectable?(port) = OpenLanes::Apps::Probe.listening?(port, timeout: 0.2)

  def transitions = published.map { [it.process, it.state] }

  context "with an API and a web process" do
    let(:record) { File.join(dir, "web-saw-api") }
    let(:definition) do
      app(process("api", "--delay 0.3"),
        process("web", "--record #{record} --sibling-env PORT_API", ready: "/", preview: true))
    end

    before { supervisor.start }

    it "starts the second only once the first is ready" do
      expect(File.read(record)).to start_with("answered #{supervisor.port("api")}")
    end

    it "gives each the lowest free ports from the floor, and tells every process every port" do
      api, web = supervisor.port("api"), supervisor.port("web")
      expect([api, web - api]).to match([be >= 11_100, be_positive])
      expect(File.read(record).split.last.to_i).to eq(api)
    end

    it "publishes starting then ready for each, in order" do
      expect(transitions).to eq([%w[api starting], %w[api ready], %w[web starting], %w[web ready]])
    end

    it "checks the preview process's framing once it is ready" do
      expect(supervisor.preview).to have_attributes(process: "web", framing: "frame", url: "http://127.0.0.1:#{supervisor.port("web")}/")
    end

    it "reports the latest status of each in start order" do
      expect(supervisor.statuses.map { [it.process, it.state] }).to eq([%w[api ready], %w[web ready]])
    end

    it "stops every process and frees every port" do
      pids = %w[api web].map { supervisor.pid(it) }
      ports = %w[api web].map { supervisor.port(it) }
      supervisor.stop
      expect(pids.map { alive?(it) }).to eq([false, false])
      expect(ports.map { connectable?(it) }).to eq([false, false])
      expect(registry.entries).to be_empty
      expect(transitions.last(2)).to eq([%w[web stopped], %w[api stopped]])
    end
  end

  context "when the preview process refuses framing" do
    let(:definition) { app(process("web", "--deny", preview: true)) }

    before { supervisor.start }

    it "says window" do
      expect(supervisor.preview.framing).to eq("window")
    end
  end

  context "when a later process exits before it is ready" do
    let(:definition) { app(process("api"), process("web", "--exit 3")) }

    it "fails the start with the reason, and leaves nothing running" do
      expect { supervisor.start }.to raise_error(described_class::StartFailed, /web exited with status 3 before it was ready.*web starting as/m)
      expect(transitions).to include(%w[api stopped], %w[web failed])
      expect(registry.entries).to be_empty
      expect((OpenLanes::Execution::Child.live - children_before).select(&:alive?)).to be_empty
    end
  end

  context "when a process never listens" do
    let(:ready_timeout) { 0.5 }
    let(:definition) { app(process("web", "--silent")) }

    it "fails once the timeout passes, naming the port it was given" do
      expect { supervisor.start }.to raise_error(described_class::StartFailed, /web was given port \d+ and nothing answered there within 0.5 s/)
      expect((OpenLanes::Execution::Child.live - children_before).select(&:alive?)).to be_empty
    end
  end

  context "when a process listens on a port other than the one it was given" do
    let(:ready_timeout) { 1 }
    let(:elsewhere) { TCPServer.new("127.0.0.1", 0).then { |s| s.addr[1].tap { s.close } } }
    let(:definition) { app(process("web", "--port #{elsewhere}")) }

    it "fails with a reason naming the port it was given" do
      expect { supervisor.start }.to raise_error(described_class::StartFailed) { |e|
        expect(e.message).to match(/web was given port (\d+) and nothing answered there/)
        expect(e.message[/port (\d+)/, 1].to_i).not_to eq(elsewhere)
      }
      expect(connectable?(elsewhere)).to be(false)
    end
  end

  context "when the readiness path never answers 2xx or 3xx" do
    let(:ready_timeout) { 0.5 }
    let(:probe) { Class.new { def self.ready?(_port, path: nil) = path.nil? } }
    let(:supervisor) do
      described_class.new(definition:, root: dir, plan: "012.00", branch: "b", registry:, probe:, ready_timeout:, poll: 0.05)
    end
    let(:definition) { app(process("web", ready: "/up")) }

    it "names the path in the reason" do
      expect { supervisor.start }.to raise_error(described_class::StartFailed, %r{nothing answered 2xx or 3xx on /up})
    end
  end
end
