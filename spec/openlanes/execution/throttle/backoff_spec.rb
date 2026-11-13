# frozen_string_literal: true

# Plan 060.00, item 4: how long a throttled agent waits and when it gives up.
# The random source and the sleep are handed in, so nothing here waits.
RSpec.describe OpenLanes::Execution::Throttle::Backoff do
  subject(:backoff) { described_class.new(random:, sleep: ->(seconds) { slept << seconds }, **options) }

  let(:random) { instance_double(Random, rand: 0.0) }
  let(:slept) { [] }
  let(:options) { {} }
  let(:limit) { OpenLanes::Execution::Throttle::Limit.new(kind: :rate_limit, retry_after:, detail: "429") }
  let(:retry_after) { nil }
  let(:waits) { backoff.waits }

  it "doubles each wait up to the cap, then stops at the retry count" do
    expect(Array.new(9) { waits.next(limit) }).to eq([30, 60, 120, 240, 480, 600, 600, 600, nil])
  end

  context "with jitter" do
    let(:random) { instance_double(Random, rand: 1.0) }

    it "adds up to a quarter of the wait" do
      expect(waits.next(limit)).to eq(37.5)
    end
  end

  context "when the provider names its wait" do
    let(:retry_after) { 7.0 }

    it "believes it over the schedule" do
      expect([waits.next(limit), waits.next(limit)]).to eq([7.0, 7.0])
    end
  end

  context "when the provider asks for longer than the budget" do
    let(:retry_after) { 4 * 3600.0 }

    it "gives up at once, saying what was asked" do
      expect([waits.next(limit), waits.surrender(limit)])
        .to eq([nil, "rate limited: gave up after 0 retries and 0s of waiting, and the provider asks for 14400s more (429)"])
    end
  end

  context "when the waits together would pass the budget" do
    let(:options) { { budget: 100 } }

    it "stops short of it" do
      expect([Array.new(3) { waits.next(limit) }, waits.surrender(limit)])
        .to eq([[30, 60, nil], "rate limited: gave up after 2 retries and 90s of waiting (429)"])
    end
  end

  describe "#pause" do
    it "waits the whole time a slice at a time" do
      expect([backoff.pause(2.5) { false }, slept]).to eq([true, [1, 1, 0.5]])
    end

    it "is cut short the moment the agent is stopped" do
      expect([backoff.pause(30) { slept.size >= 2 }, slept]).to eq([false, [1, 1]])
    end
  end
end
