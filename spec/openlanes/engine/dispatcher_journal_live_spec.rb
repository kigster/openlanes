# frozen_string_literal: true

require_relative "../live/live_context"

# While the round is still running: a round killed later keeps what it
# printed before the kill.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  let(:job) { dispatcher.running.first }
  let(:journal) { OpenLanes::Plans::Journal }
  let(:entries) { OpenLanes::Plans::PlanState.for(path_of("001.00")).journal(job.task.agent.name).flat_map(&:entries) }

  before do
    building("001.00", "tax-rule-dsl")
    start_agents
    job.journal = journal.scan(journal.line("decision", "Integer cents"))
    dispatcher.tick
  end

  it "writes an entry on the tick after it was printed" do
    expect(entries.map(&:text)).to eq(["Integer cents"])
  end

  it "does not write it twice on the next tick" do
    job.journal += journal.scan(journal.line("done", "U1"))
    dispatcher.tick
    expect(entries.map(&:text)).to eq(["Integer cents", "U1"])
  end
end
