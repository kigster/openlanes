# frozen_string_literal: true

RSpec.describe OpenLanes::Clock do
  describe OpenLanes::Clock::System do
    it "tells the real time" do
      expect(described_class.now).to be_within(5).of(Time.now)
    end

    it "keeps a monotonic clock that never runs backwards" do
      first = described_class.monotonic
      expect(described_class.monotonic).to be >= first
    end

    it "sleeps for real" do
      allow(Kernel).to receive(:sleep)
      described_class.sleep(0.01)
      expect(Kernel).to have_received(:sleep).with(0.01)
    end
  end

  describe OpenLanes::Clock::Fake do
    subject(:clock) { described_class.new(now: Time.utc(2026, 10, 20, 12)) }

    it "stands still until told to move" do
      expect(clock.now).to eq(Time.utc(2026, 10, 20, 12))
    end

    it "moves wall and monotonic time together when advanced" do
      clock.advance(90)
      expect([clock.now, clock.monotonic]).to eq([Time.utc(2026, 10, 20, 12, 1, 30), 90.0])
    end

    it "advances instead of blocking when slept on" do
      allow(Kernel).to receive(:sleep)
      clock.sleep(3600)
      aggregate_failures do
        expect(clock.now).to eq(Time.utc(2026, 10, 20, 13))
        expect(Kernel).not_to have_received(:sleep)
      end
    end

    it "loses no advance made from several threads at once" do
      Array.new(8) { Thread.new { 100.times { clock.advance(1) } } }.each { it.join(5) }
      expect(clock.monotonic).to eq(800.0)
    end
  end
end
