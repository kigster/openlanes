# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::Crashes do
  subject(:crashes) { described_class.new(clock:) }

  let(:clock) { OpenLanes::Clock::Fake.new }

  context "with one crash" do
    before { crashes.record }

    it { expect(crashes.delay).to eq(1) }
    it { expect(crashes.exhausted?).to be(false) }
  end

  context "with two" do
    before { 2.times { crashes.record } }

    it("waits twice as long") { expect(crashes.delay).to eq(2) }
  end

  context "with three inside five minutes" do
    before { 3.times { crashes.record.then { clock.advance(60) } } }

    it { expect(crashes.exhausted?).to be(true) }
    it { expect(crashes.reason).to eq("3 crashes in 5m") }
  end

  context "with three spread over more than five minutes" do
    before { 3.times { crashes.record.then { clock.advance(200) } } }

    it("forgets the old ones") { expect(crashes.exhausted?).to be(false) }
  end

  context "with many, in a long window" do
    subject(:crashes) { described_class.new(clock:, limit: 100) }

    before { 10.times { crashes.record } }

    it("never waits longer than LONGEST") { expect(crashes.delay).to eq(described_class::LONGEST) }
  end
end
