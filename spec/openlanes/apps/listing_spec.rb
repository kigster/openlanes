# frozen_string_literal: true

RSpec.describe OpenLanes::Apps::Listing do
  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:now) { Time.utc(2026, 10, 14, 12, 0, 0) }

  def status(plan, process, state = "ready") = OpenLanes::Apps::Status.new(plan:, branch: "b", process:, state:, port: 11_100, at: now)

  it "keeps the apps under this machine's key, not this checkout's" do
    described_class.write(store:, keys:, plan: "012.00", statuses: [status("012.00", "web")], now:)
    other_checkout = keys.with(node: "aaaa:cccc")
    expect(described_class.read(store:, keys: other_checkout, now:).map { it["process"] }).to eq(["web"])
  end

  it "reads every plan's processes, plans in order, processes as written" do
    described_class.write(store:, keys:, plan: "014.00", statuses: [status("014.00", "web")], now:)
    described_class.write(store:, keys:, plan: "012.00", statuses: [status("012.00", "api"), status("012.00", "web")], now:)
    expect(described_class.read(store:, keys:, now:).map { [it["plan"], it["process"]] })
      .to eq([%w[012.00 api], %w[012.00 web], %w[014.00 web]])
  end

  it "drops a plan whose heartbeat is older than TTL, from the store too" do
    described_class.write(store:, keys:, plan: "012.00", statuses: [status("012.00", "web")], now: now - 31)
    expect(described_class.read(store:, keys:, now:)).to eq([])
    expect(store.hgetall(keys.apps)).to eq({})
  end

  it "drops a field that is not an entry" do
    store.hset(keys.apps, "012.00", "not json")
    expect(described_class.read(store:, keys:, now:)).to eq([])
  end

  it "removes one plan" do
    described_class.write(store:, keys:, plan: "012.00", statuses: [status("012.00", "web")], now:)
    described_class.remove(store:, keys:, plan: "012.00")
    expect(store.hgetall(keys.apps)).to eq({})
  end
end
