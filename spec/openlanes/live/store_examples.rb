# frozen_string_literal: true

# What {OpenLanes::Live::Store} and {OpenLanes::Live::MemoryStore} both
# promise. The fake earns its place in the suite by passing exactly the
# examples the real Redis passes; an example only one of them could pass
# belongs in that one's own spec.
#
# The including group provides `store`, empty at the start of each example.
RSpec.shared_examples "a live store" do
  describe "strings" do
    it "keeps a value until it is deleted" do
      store.set("k", "v")
      expect(store.get("k")).to eq("v")
      expect(store.del("k", "absent")).to eq(1)
      expect(store.get("k")).to be_nil
    end

    it "writes NX only when the key is free" do
      aggregate_failures do
        expect(store.set("k", "first", nx: true)).to be(true)
        expect(store.set("k", "second", nx: true)).to be(false)
        expect(store.get("k")).to eq("first")
      end
    end

    it "gives EX a time to live, and EXPIRE a new one" do
      store.set("k", "v", ex: 30)
      aggregate_failures do
        expect(store.ttl("k")).to be_between(29, 30)
        expect(store.expire("k", 90)).to be(true)
        expect(store.ttl("k")).to be_between(89, 90)
        expect(store.expire("absent", 5)).to be(false)
        expect(store.ttl("absent")).to eq(-2)
      end
    end

    it "reports a key without an expiry as -1" do
      store.set("k", "v")
      expect(store.ttl("k")).to eq(-1)
    end

    it "deletes nothing when asked to delete nothing" do
      expect(store.del).to eq(0)
    end

    it "compares before it deletes" do
      store.set("claim", "mine")
      aggregate_failures do
        expect(store.compare_and_delete("claim", "theirs")).to be(false)
        expect(store.get("claim")).to eq("mine")
        expect(store.compare_and_delete("claim", "mine")).to be(true)
        expect(store.get("claim")).to be_nil
      end
    end

    it "compares before it extends" do
      store.set("claim", "mine", ex: 10)
      aggregate_failures do
        expect(store.compare_and_expire("claim", "theirs", 90)).to be(false)
        expect(store.ttl("claim")).to be <= 10
        expect(store.compare_and_expire("claim", "mine", 90)).to be(true)
        expect(store.ttl("claim")).to be > 80
        expect(store.compare_and_expire("absent", "mine", 90)).to be(false)
      end
    end
  end

  describe "hashes" do
    it "sets, reads and removes fields" do
      aggregate_failures do
        expect(store.hset("h", "a", "1")).to be(true)
        expect(store.hset("h", "a", "2")).to be(false)
        store.hset("h", "b", "3")
        expect(store.hget("h", "a")).to eq("2")
        expect(store.hget("h", "zz")).to be_nil
        expect(store.hgetall("h")).to eq("a" => "2", "b" => "3")
        expect(store.hdel("h", "a", "zz")).to eq(1)
        expect(store.hdel("h")).to eq(0)
        expect(store.hgetall("absent")).to eq({})
      end
    end
  end

  describe "streams" do
    let(:ids) { Array.new(3) { |i| store.xadd("s", { seq: i, json: "{}" }) } }
    let(:first) { store.xadd("s", { n: 1 }) }

    it "appends entries in order, with increasing ids" do
      aggregate_failures do
        expect(ids).to eq(ids.sort_by { it.split("-").map(&:to_i) })
        expect(store.xlen("s")).to eq(3)
        expect(store.xrange("s").map { it.fields["seq"] }).to eq(%w[0 1 2])
        expect(store.xrevrange("s", count: 1).first.fields).to eq("seq" => "2", "json" => "{}")
        expect(store.xrange("s", count: 2).size).to eq(2)
        expect(store.xrange("s", start: ids[1]).map(&:id)).to eq(ids.drop(1))
        expect(store.xrevrange("s", stop: ids[1]).map(&:id)).to eq(ids.first(2).reverse)
      end
    end

    it "trims to about MAXLEN entries" do
      300.times { |i| store.xadd("s", { n: i }, maxlen: 10) }
      expect(store.xlen("s")).to be < 300
    end

    it "reads what came after an id, and nothing for $" do
      first
      store.xadd("s", { n: 2 })
      aggregate_failures do
        expect(store.xread("s", id: first).map { it.fields["n"] }).to eq(%w[2])
        expect(store.xread("s", id: "0").size).to eq(2)
        expect(store.xread("s", id: "$")).to eq([])
        expect(store.xread("absent", id: "0")).to eq([])
      end
    end

    it "answers nothing for a stream that does not exist" do
      aggregate_failures do
        expect(store.xrange("absent")).to eq([])
        expect(store.xlen("absent")).to eq(0)
      end
    end
  end

  describe "a consumer group" do
    let(:delivered) { store.xreadgroup("cmd", "engine", "me") }

    before { store.xadd("cmd", { json: "one" }) }

    it "is created once, with its stream, and asking again is not an error" do
      aggregate_failures do
        expect(store.xgroup_create("cmd", "engine")).to be(true)
        expect(store.xgroup_create("cmd", "engine")).to be(false)
        expect(store.xgroup_create("fresh", "engine")).to be(true)
        expect(store.xlen("fresh")).to eq(0)
      end
    end

    it "delivers each entry once, keeps it pending until acked, and redelivers the pending" do
      store.xgroup_create("cmd", "engine")
      delivered
      aggregate_failures do
        expect(delivered.map { it.fields["json"] }).to eq(%w[one])
        expect(store.xreadgroup("cmd", "engine", "me")).to eq([])
        expect(store.xreadgroup("cmd", "engine", "me", id: "0").map(&:id)).to eq(delivered.map(&:id))
        expect(store.xack("cmd", "engine", *delivered.map(&:id))).to eq(1)
        expect(store.xack("cmd", "engine")).to eq(0)
        expect(store.xreadgroup("cmd", "engine", "me", id: "0")).to eq([])
      end
    end

    it "starts after what is there when created from $" do
      store.xgroup_create("cmd", "late", from: "$")
      store.xadd("cmd", { json: "two" })
      expect(store.xreadgroup("cmd", "late", "me").map { it.fields["json"] }).to eq(%w[two])
    end
  end

  describe "SCAN" do
    it "finds every key under a prefix, glob characters taken literally" do
      store.set("openlanes:a*b:x", "1")
      store.hset("openlanes:a*b:h", "f", "v")
      store.set("openlanes:aXb:y", "1")
      store.set("other", "1")
      expect(store.scan("openlanes:a*b:")).to eq(%w[openlanes:a*b:h openlanes:a*b:x])
    end
  end

  describe "MULTI" do
    let(:entry) do
      store.xgroup_create("cmd", "engine")
      store.xadd("cmd", { json: "c" })
      store.xreadgroup("cmd", "engine", "me").first
    end

    it "applies every write of the block" do
      store.multi do |tx|
        tx.set("snap", "{}", ex: 30)
        tx.hset("done", "id1", "reply")
        tx.xadd("replies", { json: "reply" }, maxlen: 1000)
        tx.xack("cmd", "engine", entry.id)
        tx.expire("snap", 60)
      end
      aggregate_failures do
        expect(store.get("snap")).to eq("{}")
        expect(store.ttl("snap")).to be > 30
        expect(store.hget("done", "id1")).to eq("reply")
        expect(store.xlen("replies")).to eq(1)
        expect(store.xreadgroup("cmd", "engine", "me", id: "0")).to eq([])
      end
    end

    it "does nothing for an empty block" do
      expect(store.multi { nil }).to be_nil
    end
  end

  it "answers PING" do
    expect(store.ping).to be(true)
  end
end
