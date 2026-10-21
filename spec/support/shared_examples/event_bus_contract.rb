# frozen_string_literal: true

# What every {OpenLanes::Live::EventBus} promises. The including group
# provides `bus`, over an empty store.
RSpec.shared_examples "an event bus" do
  def drain(subscription, count)
    Array.new(count) { subscription.next_message(1.0) }.compact
  end

  it "delivers a publish to a channel subscriber" do
    subscription = bus.subscribe(channels: ["c:#{bus.db}"])
    sleep 0.05 until bus.publish("c:#{bus.db}", "hello").positive?
    expect(drain(subscription, 1).first).to eq(["c:#{bus.db}", "hello"])
  ensure
    subscription&.close
  end

  it "delivers to a pattern subscriber" do
    subscription = bus.subscribe(patterns: ["room:*"])
    sleep 0.05 until bus.publish("room:1", "hi").positive?
    expect(drain(subscription, 1).first).to eq(["room:1", "hi"])
  ensure
    subscription&.close
  end

  it "appends in order, with stream ids that sort as they were written" do
    ids = %w[a b c].map { bus.append("s", { json: it }) }
    entries = bus.store.xrange("s")
    aggregate_failures do
      expect(ids).to all(match(/\A\d+-\d+\z/))
      expect(entries.map(&:id)).to eq(ids)
      expect(entries.map { it.fields["json"] }).to eq(%w[a b c])
    end
  end

  it "trims to maxlen and keeps the newest" do
    30.times { bus.append("s", { json: it.to_s }, maxlen: 5) }
    entries = bus.store.xrange("s")
    aggregate_failures do
      expect(entries.size).to be_between(5, 30)
      expect(entries.last.fields["json"]).to eq("29")
    end
  end

  it "applies a transaction's appends and writes together" do
    bus.transaction do |tx|
      tx.append("s", { json: "one" })
      tx.set("k", "v")
      tx.append("s", { json: "two" })
    end
    aggregate_failures do
      expect(bus.store.xrange("s").map { it.fields["json"] }).to eq(%w[one two])
      expect(bus.store.get("k")).to eq("v")
    end
  end

  it "applies nothing of a transaction whose block raised" do
    expect do
      bus.transaction do |tx|
        tx.append("s", { json: "x" })
        raise "no"
      end
    end.to raise_error(RuntimeError, "no")
    expect(bus.store.xrange("s")).to be_empty
  end

  it "is the bus it is asked for again" do
    expect(OpenLanes::Live::EventBus.for(bus)).to be(bus)
  end
end
