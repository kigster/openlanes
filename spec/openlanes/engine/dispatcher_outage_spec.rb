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
end
