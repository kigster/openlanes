# frozen_string_literal: true

require "json"
require "rbconfig"

# The loop behind `openlanes app start`, against real processes and the
# in-memory store; each tick runs the example's block instead of sleeping.
RSpec.describe OpenLanes::Apps::Runner do
  let(:root) { File.realpath(Dir.mktmpdir("openlanes-runner")) }
  let(:server) { File.expand_path("../../fixtures/apps/servers/server.rb", __dir__) }
  let(:registry) { OpenLanes::Apps::Ports.new(path: File.join(root, "ports.json"), **PortWindow.bounds) }
  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:said) { [] }
  let(:ticks) { [] }
  let(:on_tick) { [nil] }
  let(:definition) do
    OpenLanes::Apps::Definition.new(kind: "web",
      processes: [process("db"), process("api", restart_on: ["api/*.rb"]), process("web", preview: true)])
  end
  let(:runner) do
    described_class.new(definition:,
      root:,
      plan: "012.00",
      branch: "kig/012.00-app",
      store:,
      keys:,
      say: ->(line) { said << line },
      sleeper: lambda { |_|
        ticks << runner.supervisor.statuses.map { [it.process, it.state] }
        on_tick.first&.call(ticks.size)
      },
      supervisor: { registry:, poll: 0.05 })
  end

  def process(name, **) = OpenLanes::Apps::ProcessSpec.new(name:, start: "#{RbConfig.ruby} #{server} --name #{name} --port-env PORT_#{name.upcase}", **)

  after { FileUtils.rm_rf(root) }

  def command(plan: "012.00", **fields) = store.xadd(keys.app_commands, { json: JSON.generate(plan:, **fields) })

  def listed = OpenLanes::Apps::Listing.read(store:, keys:)

  def run(&block)
    on_tick[0] = block
    runner.call
  end

  it "lists every process on the board while it runs, then takes the app off when it stops" do
    seen = nil
    run do |tick|
      seen = listed.map { [it["process"], it["state"]] }
      runner.stopping.make_true if tick == 1
    end
    expect(seen).to eq([%w[db ready], %w[api ready], %w[web ready]])
    expect(listed).to eq([])
  end

  it "stops when the page asks, with every port free" do
    run { |tick| command(action: "stop") if tick == 1 }
    expect(said.last(4).map { it[/\A\S+ \S+/] }).to eq(["stopping: asked", "web stopped", "api stopped", "db stopped"])
    expect(registry.entries).to eq({})
  end

  it "restarts every process but the previewed one for Restart backend, in declared order" do
    pids = {}
    run do |tick|
      pids[tick] = %w[db api web].to_h { [it, runner.supervisor.pid(it)] }
      command(action: "restart", target: "backend") if tick == 1
      runner.stopping.make_true if tick == 2
    end
    expect(pids[2]["web"]).to eq(pids[1]["web"])
    expect(%w[db api].map { pids[2][it] == pids[1][it] }).to eq([false, false])
    expect(said.grep(/\Arestarting/)).to eq(["restarting db: asked from the page", "restarting api: asked from the page"])
  end

  it "restarts one process named by the page" do
    run do |tick|
      command(action: "restart", target: "api") if tick == 1
      runner.stopping.make_true if tick == 2
    end
    expect(said.grep(/\Arestarting/)).to eq(["restarting api: asked from the page"])
  end

  it "ignores what was asked of another plan, and before it started" do
    command(action: "stop")
    run do |tick|
      command(plan: "014.00", action: "stop") if tick == 1
      runner.stopping.make_true if tick == 3
    end
    expect(ticks.size).to eq(3)
  end

  it "restarts a process whose files changed" do
    FileUtils.mkdir_p(File.join(root, "api"))
    File.write(File.join(root, "api", "handler.rb"), "1")
    run do |tick|
      File.write(File.join(root, "api", "handler.rb"), "22") if tick == 1
      runner.stopping.make_true if tick == 2
    end
    expect(said.grep(/\Arestarting/)).to eq(["restarting api: its files changed"])
  end

  context "when the app does not start" do
    let(:definition) { OpenLanes::Apps::Definition.new(kind: "web", processes: [process("web", preview: true).with(start: "exit 4")]) }

    it "raises with the reason and leaves the failure on the board for the tab" do
      expect { runner.call }.to raise_error(OpenLanes::Apps::Supervisor::StartFailed, /status 4/)
      expect(listed.map { [it["process"], it["state"]] }).to eq([%w[web failed]])
    end
  end

  context "without Redis" do
    let(:store) { nil }

    it "runs the app all the same" do
      seen = nil
      run do |tick|
        seen = runner.supervisor.statuses.map(&:state)
        runner.stopping.make_true if tick == 1
      end
      expect(seen).to eq(%w[ready ready ready])
    end
  end

  context "when Redis goes away" do
    let(:store) do
      OpenLanes::Live.memory_store.tap do |s|
        s.define_singleton_method(:hset) { |*| raise OpenLanes::Live::Unavailable, "gone" }
      end
    end

    it "says so once and keeps the app running" do
      run { |tick| runner.stopping.make_true if tick == 2 }
      expect(said.grep(/Redis/)).to eq(["Redis: gone"])
    end
  end
end
