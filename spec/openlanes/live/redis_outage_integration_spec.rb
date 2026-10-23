# frozen_string_literal: true

require "json"
require_relative "live_context"
require_relative "../../support/redis_server"

# Plan 022's integration check: nothing stubbed between the engine and
# Redis. A real redis-server is stopped and started under a running engine,
# and what the page would read comes back out of that same Redis. Only the
# clocks are the spec's, so the outage's grace and its Fibonacci probes pass
# in ticks rather than in real seconds.
RSpec.describe "A Redis outage under a running engine", :tree do
  include_context "with a live run"

  let(:server) { RedisServer.new.start }
  let(:store) { OpenLanes::Live::Store.new(url: server.url, timeout: 0.5) }
  let(:time) { [0.0] }
  let(:base) { Time.now.utc.floor }
  let(:wall) { -> { base + time[0] } }
  let(:outage) { OpenLanes::Live::Outage.new(store:, limit: 3600.0, clock: -> { time[0] }, wall:) }
  let(:session) do
    OpenLanes::Live::Session.new(store:,
      root: plans_root,
      tree:,
      agents:,
      node:,
      repo: "github.com/example/openlanes",
      clock: wall,
      outage:)
  end
  let(:dispatcher) do
    OpenLanes::Engine::Dispatcher.new(runner:,
      state:    OpenLanes::Engine.state_file(tree),
      sleeper:  ->(_) {},
      on_board: session.on_board)
  end
  let(:lines) { [] }

  before do
    skip RedisServer.missing if RedisServer.missing
    allow(OpenLanes::UI).to receive(:log) { |line, **| lines << line }
    building("001.00", "tax-rule-dsl")
    session.attach(dispatcher)
  end

  after do
    OpenLanes::Execution::Control.reset!
    server.destroy
    store.close if store.respond_to?(:close)
  end

  def snapshot = JSON.parse(store.get(session.keys.snapshot))
  def control = File.read(dispatcher.running.first.handle.control)

  # One tick a second on the spec's clocks, until the block says stop.
  def tick_until(limit: 60)
    limit.times do
      time[0] += 1
      dispatcher.tick
      return if yield
    end
  end

  # An agent at work, a run-state change kept in both copies, one snapshot
  # published to the real Redis.
  def publish_once
    start_agents
    session.run_state.choose_model("001.00/luke-backend", "opus")
    dispatcher.tick
  end

  it "publishes to the real Redis before anything goes wrong" do
    publish_once
    expect([snapshot["run"]["outage"], store.ping]).to eq([nil, true])
  end

  it "pauses on the outage and resumes when the same Redis comes back" do
    publish_once

    server.stop
    tick_until { outage.paused? }
    calls = executor.calls.dup
    aggregate_failures "while Redis is down" do
      expect(OpenLanes::Execution::Control).to be_paused
      expect(control.strip).to eq("PAUSE")
      expect(executor.calls).to eq(calls)
      expect(lines).to include(/\ARedis has not answered for \d+s: pausing every agent/)
    end

    server.start
    tick_until { !outage.paused? }
    aggregate_failures "once Redis answers" do
      expect(OpenLanes::Execution::Control).not_to be_paused
      expect(control.strip).to eq("RESUME")
      expect(lines).to include(/\ARedis is back after \d+s \(by heartbeat\), run state from redis; resuming\z/)
      expect(snapshot["run"]["outage"]).to include("measured_by" => "heartbeat", "reconciled_from" => "redis", "seconds" => be_positive)
    end
  end

  it "takes the run state from the file when Redis comes back empty" do
    publish_once
    server.stop
    server.wipe
    tick_until { outage.paused? }
    server.start
    tick_until { !outage.paused? }

    expect(snapshot["run"]["outage"]).to include("measured_by" => "clock", "reconciled_from" => "file")
  end
end
