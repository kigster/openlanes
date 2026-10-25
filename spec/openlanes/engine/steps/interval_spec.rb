# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Steps::Interval do
  subject(:interval) { described_class.new(30) }

  let(:now) { [100.0] }

  before { allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { now.first } }

  it "is due at once, then not again until the interval has passed" do
    first = interval.due?
    now[0] = 129.0
    early = interval.due?
    now[0] = 130.0

    expect([first, early, interval.due?]).to eq([true, false, true])
  end
end
