# frozen_string_literal: true

require_relative "../live/live_context"

# W32: while Redis is lost the agents under way are paused, and nobody new
# starts, since no plan claim can be checked.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  before do
    building("001.00", "first")
    building("002.00", "second")
  end

  after { OpenLanes::Execution::Control.reset! }

  it "starts nobody while agents are paused, and starts them once Redis is back" do
    OpenLanes::Execution::Control.pause!
    dispatcher.tick
    expect(dispatcher.running).to be_empty

    OpenLanes::Execution::Control.resume!
    start_agents
    expect(dispatcher.running).not_to be_empty
  end

  # Plan 022: once Redis answers, the session says how long it was gone and
  # publishes that as `run.outage`.
  describe "the live session" do
    subject(:session) { OpenLanes::Live::Session.new(store:, root: plans_root, tree:, agents:, node:, repo: "github.com/example/openlanes") }

    let(:window) do
      OpenLanes::Live::Outage::Window.new(started_at: Time.utc(2026, 10, 16, 18, 40, 0),
        ended_at: Time.utc(2026, 10, 16, 18, 41, 12),
        seconds: 72.0)
    end

    before do
      allow(OpenLanes::UI).to receive(:log)
      session.attach(dispatcher)
    end

    it "reports the outage and publishes it as run.outage" do
      report = session.recover(window)
      aggregate_failures do
        expect(OpenLanes::UI).to have_received(:log).with("Redis is back after 72s (by clock), no run state to reconcile; resuming")
        expect(session.publisher.outage).to eq(report.to_h)
        expect(report.to_h).to include(seconds: 72, measured_by: "clock")
      end
    end

    it "is what the outage calls when Redis answers again" do
      session.outage.instance_variable_get(:@resumed).each { it.call(window) }
      expect(session.publisher.outage).to include(seconds: 72)
    end
  end
end
