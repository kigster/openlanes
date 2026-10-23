# frozen_string_literal: true

require "json"

RSpec.describe OpenLanes::Live::OutageReport do
  subject(:report) { described_class.new(store:, keys:, node:, window:, reconciled_from:) }

  let(:store) { OpenLanes::Live.memory_store }
  let(:node) do
    OpenLanes::Live::Node.new(id: "3f9a0c7be21d44a8f6031c5d",
      user: "dana",
      host: "studio-mini",
      ip: "10.0.4.12",
      checkout: "~/github/example/openlanes",
      checkout_id: "a1b2c3d4e5f6")
  end
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/example/openlanes", node: node.name) }
  let(:started) { Time.utc(2026, 10, 16, 18, 40, 0) }
  let(:window) do
    OpenLanes::Live::Outage::Window.new(started_at: started, ended_at: started + 72, seconds: 70.4)
  end

  def beat(at) = store.hset(keys.nodes, node.name, JSON.generate(node.wire(heartbeat_at: at)))

  context "when Redis kept this node's last heartbeat (no loss)" do
    let(:reconciled_from) { :redis }

    before { beat(started - 2) }

    it "measures from the heartbeat" do
      expect(report.to_h).to eq(started_at: "2026-10-16T18:39:58Z",
        ended_at: "2026-10-16T18:41:12Z",
        seconds: 74,
        measured_by: "heartbeat",
        reconciled_from: "redis")
    end

    it "says so in one line" do
      expect(report.line).to eq("Redis is back after 74s (by heartbeat), run state from redis; resuming")
    end
  end

  context "when Redis came back from an older snapshot (RDB rollback)" do
    let(:reconciled_from) { :file }

    before { beat(started - 3600) }

    it "falls back to the engine's own clock, and the file wins" do
      expect(report.to_h).to include(started_at: "2026-10-16T18:40:00Z",
        seconds: 70,
        measured_by: "clock",
        reconciled_from: "file")
    end

    it "says so in one line" do
      expect(report.line).to eq("Redis is back after 70s (by clock), run state from file; resuming")
    end
  end

  context "when Redis came back empty" do
    let(:reconciled_from) { nil }

    it "measures by clock and has nothing to reconcile" do
      expect([report.measured_by, report.to_h[:reconciled_from], report.line])
        .to eq(["clock", nil, "Redis is back after 70s (by clock), no run state to reconcile; resuming"])
    end
  end

  context "when the heartbeat field is not JSON" do
    let(:reconciled_from) { :file }

    before { store.hset(keys.nodes, node.name, "{") }

    it "measures by clock" do
      expect(report.measured_by).to eq("clock")
    end
  end
end
