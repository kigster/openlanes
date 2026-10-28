# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Probes do
  subject(:probes) { described_class.new(store:, keys:, owner: "node-a", prober:) }

  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "test", node: "m:1") }
  let(:key) { keys.adapters }
  let(:lock) { keys.adapters_lock }
  let(:at) { Time.utc(2026, 10, 27, 9) }
  let(:names) { %w[claude codex] }
  let(:prober) { -> { OpenLanes::Adapters.availability(names:, runner:, at:) } }
  let(:signed_in) { OpenLanes::Adapters::ProbeRunner::Result.new(stdout: %({"loggedIn": true}), stderr: "", status: 0) }
  let(:runner) { ScriptedProbeRunner.new(installed: %w[claude], answers: { %w[claude auth status --json] => signed_in }) }

  # A store whose every call says Redis is gone, as {OpenLanes::Live::Store} does.
  let(:gone) do
    Class.new do
      def set(*, **) = raise(OpenLanes::Live::Unavailable, "Redis is unavailable")
      def get(*) = raise(OpenLanes::Live::Unavailable, "Redis is unavailable")
    end.new
  end

  describe "#refresh, winning the lock" do
    subject!(:probed) { probes.refresh }

    it { expect(probed.map { [it.name, it.available] }).to eq([["claude", true], ["codex", false]]) }
    it { expect(store.get(lock)).to eq("node-a") }
    it { expect(JSON.parse(store.get(key)).map { it["name"] }).to eq(%w[claude codex]) }
    it { expect(probes.current).to eq(probed) }
  end

  describe "#refresh, when another process holds the lock" do
    before { store.set(lock, "node-b", ex: 60) }

    it { expect(probes.refresh).to be_nil }

    it "probes nothing and writes nothing" do
      probes.refresh
      expect([runner.calls, store.get(key)]).to eq([[], nil])
    end
  end

  describe "with Redis gone" do
    let(:store) { gone }

    it "probes for itself and keeps the answer in memory" do
      probed = probes.refresh
      expect(probes.current).to eq(probed)
    end

    it "has nothing to show before its first probe" do
      expect(probes.current).to eq([])
    end
  end

  describe "#current" do
    it "is empty while nothing has been probed" do
      expect(probes.current).to eq([])
    end

    it "reads what another process wrote" do
      store.set(key, JSON.generate([OpenLanes::Adapters::Availability.down("pi", "no provider", at).wire]))
      expect(probes.current.map(&:reason)).to eq(["no provider"])
    end

    it "falls back to memory on a key it cannot read" do
      store.set(key, "{not json")
      expect(probes.current).to eq([])
    end

    # Grok on #151: Time.iso8601 raises ArgumentError, outside the old rescue.
    it "falls back to memory on a checked_at that is not a time" do
      store.set(key, JSON.generate([OpenLanes::Adapters::Availability.down("pi", "no provider", at).wire.merge(checked_at: "yesterday")]))
      expect(probes.current).to eq([])
    end
  end

  describe "#refresh, when probing raises" do
    let(:prober) { -> { raise ArgumentError, "boom" } }

    it { expect(probes.refresh).to be_nil }

    it "logs the failure" do
      logger = instance_double(SemanticLogger::Logger, warn: nil)
      allow(OpenLanes::Log).to receive(:logger).and_return(logger)
      probes.refresh
      expect(logger).to have_received(:warn).with("adapter probe failed", error: "boom")
    end
  end

  describe "#start and #stop" do
    it "probes at once, on a thread of its own, and stops when told" do
      probes.start
      Timeout.timeout(5) { sleep 0.01 until store.get(key) }
      probes.stop
      expect(probes.current.map(&:name)).to eq(%w[claude codex])
    end

    it "is started once however often it is asked" do
      probes.start
      expect(probes.start).to be(probes)
    ensure
      probes.stop
    end

    it "probes again every interval" do
      stub_const("#{described_class}::INTERVAL", 0.01)
      quick = described_class.new(store:, keys:, owner: "node-a", prober: -> { OpenLanes::Adapters.availability(names: %w[claude], runner:, at:) })
      quick.start
      Timeout.timeout(5) { sleep 0.01 until runner.calls.size >= 1 }
      # The lock outlives one round on purpose; gone, the next round wins it.
      store.del(lock)
      Timeout.timeout(5) { sleep 0.01 until runner.calls.size >= 2 }
      quick.stop
      expect(runner.calls.size).to be >= 2
    end

    it "is safe to stop when never started" do
      expect { probes.stop }.not_to raise_error
    end
  end
end
