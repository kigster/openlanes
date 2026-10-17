# frozen_string_literal: true

require_relative "../live/live_context"

# While the round is still running: a person resuming the agent by hand
# needs the id before the round settles.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  let(:job) { dispatcher.running.first }
  let(:stage) { OpenLanes::Plans::PlanState.for(path_of("001.00")).stages.first }

  before do
    building("001.00", "tax-rule-dsl")
    start_agents
    job.handle.session = "sess-live"
    dispatcher.tick
  end

  it "writes the session into the running round's stage as soon as the stream names it" do
    expect(stage.values_at("status", "session", "cwd")).to eq(["Started", "sess-live", File.dirname(plans_root)])
  end
end
