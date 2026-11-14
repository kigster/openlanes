# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Ticker, :tree do
  subject(:ticker) { described_class.new(desk, options) }

  include_context "with a dispatcher desk"

  let(:options) { OpenLanes::Engine::Dispatcher::Options.with_defaults(runner:, clock: OpenLanes::Clock::System, converter: nil) }

  it "builds every step over the one desk and hands the desk its drainer" do
    expect([ticker.assign, ticker.rows, desk.unblocking, ticker.watching])
      .to match([an_instance_of(OpenLanes::Engine::Dispatcher::Assign), an_instance_of(OpenLanes::Engine::Dispatcher::Rows),
                 ticker.unblocking, nil])
  end

  it "converts questions once a tick, after the drain" do
    calls = []
    allow(ticker.assign).to receive(:dispatch)
    ticker.call(-> { calls << :convert })
    expect(calls).to eq([:convert])
  end

  it "gives a drained plan's agents back their blocked rounds" do
    desk.remember("001.00", coder.name, :blocked, "Blocked", 1)
    ticker.send(:clear_blocked, "001.00")
    expect(desk.history[["001.00", coder.name]]).to eq([])
  end
end
