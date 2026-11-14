# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Dispatcher::Options do
  let(:clock) { OpenLanes::Clock::System }

  it "fills every keyword a caller leaves out with the dispatcher's old default" do
    options = described_class.with_defaults(runner: :runner, clock:, converter: nil)
    expect([options.state, options.stay, options.rescan, options.sleeper])
      .to eq([nil, false, OpenLanes::Engine::Dispatcher::RESCAN, nil])
  end

  it "keeps what a caller passes over the default" do
    expect(described_class.with_defaults(runner: :runner, clock:, converter: nil, stay: true, rescan: 2))
      .to have_attributes(stay: true, rescan: 2)
  end

  it "hands the desk the fields it is built from" do
    setup = described_class.with_defaults(runner: :runner, clock:, converter: nil, rounds: 2).desk_setup
    expect([setup.runner, setup.rounds]).to eq([:runner, 2])
  end
end
