# frozen_string_literal: true

require_relative "store_examples"

RSpec.describe OpenLanes::Live::MemoryStore do
  subject(:store) { described_class.new(clock: -> { clock.first }) }

  let(:clock) { [1000.0] }

  it_behaves_like "a live store"

  it "names itself as no network address" do
    expect([store.url, store.close]).to eq(["memory://", nil])
  end

  context "when the clock passes a key's expiry" do
    before do
      store.set("k", "v", ex: 30)
      store.set("claim", "mine", ex: 30)
      store.hset("h", "f", "v")
      store.expire("h", 30)
    end

    let(:later) { 1031.0 }

    it "forgets the key, as Redis would" do
      clock[0] = later
      aggregate_failures do
        expect(store.get("k")).to be_nil
        expect(store.hgetall("h")).to eq({})
        expect(store.compare_and_delete("claim", "mine")).to be(false)
        expect(store.set("claim", "theirs", nx: true)).to be(true)
        expect(store.scan("")).to eq(%w[claim])
      end
    end
  end

  it "never waits on a blocking read" do
    expect(store.xread("s", id: "$", block: 5000)).to eq([])
  end

  context "when a pending entry is trimmed away" do
    let!(:pending) do
      store.xgroup_create("cmd", "engine")
      store.xadd("cmd", { json: "first" })
      store.xreadgroup("cmd", "engine", "me").first
    end

    before { store.xadd("cmd", { json: "second" }, maxlen: 1) }

    it "keeps it as an id without fields" do
      expect(store.xreadgroup("cmd", "engine", "me", id: "0")).to eq([OpenLanes::Live::Store::Entry.new(id: pending.id, fields: {})])
    end
  end

  it "refuses to read through a group nobody created" do
    expect { store.xreadgroup("cmd", "engine", "me") }.to raise_error(OpenLanes::Live::GroupMissing, /NOGROUP/)
  end

  it "acknowledges nothing for a group nobody created" do
    expect(store.xack("cmd", "engine", "1-0")).to eq(0)
  end

  it "removes a hash whose last field goes, and ignores one that is not there" do
    store.hset("h", "f", "v")
    aggregate_failures do
      expect(store.hdel("h", "f")).to eq(1)
      expect(store.scan("h")).to eq([])
      expect(store.hdel("absent", "f")).to eq(0)
    end
  end

  it "numbers entries added within one millisecond in sequence" do
    allow(Time).to receive(:now).and_return(Time.at(5))
    expect(Array.new(2) { store.xadd("s", { n: 1 }) }).to eq(%w[5000-0 5000-1])
  end

  context "with entries a second apart" do
    before do
      allow(Time).to receive(:now).and_return(Time.at(5), Time.at(6))
      store.xadd("s", { n: 1 })
      store.xadd("s", { n: 2 })
      store.xgroup_create("s", "g", from: "5000")
    end

    it "reads ranges and groups bounded by bare millisecond ids" do
      aggregate_failures do
        expect(store.xrange("s", start: "5001", stop: "6000").map { it.fields["n"] }).to eq(%w[2])
        expect(store.xread("s", id: "5000").map { it.fields["n"] }).to eq(%w[2])
        expect(store.xreadgroup("s", "g", "me").map { it.fields["n"] }).to eq(%w[2])
      end
    end
  end
end
