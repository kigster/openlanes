# frozen_string_literal: true

require_relative "../live/live_context"

# What the loop does for a compaction (W28): it asks the running agent's
# handle for one, says which CLI the agent is on, shows the session on the
# board, and gives the round back when the agent was stopped for nothing.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  before do
    building("001.00", "tax-rule-dsl")
    start_agents
  end

  let(:job) { dispatcher.running.first }

  after { OpenLanes::Execution::Control.reset! }

  it "asks nobody who is not running" do
    expect(dispatcher.compact("001.00/nobody")).to be_nil
  end

  it "asks the running agent's handle, on the model given" do
    expect(dispatcher.compact(job.key, model: "claude-haiku-5-5").model).to eq("claude-haiku-5-5")
  end

  it "says the agent is on the CLI its definition names when the executor cannot say" do
    expect(dispatcher.adapter_for(job).name).to eq("claude")
  end

  context "with an executor that resolves profiles" do
    let(:profile) { OpenLanes::Agents::Profile.resolve(job.task.agent.with(adapter: "codex")) }

    # HeldExecutor answers no profile_for; the real executor does.
    before do
      chosen = profile
      executor.define_singleton_method(:profile_for) { |*| chosen }
    end

    it "says the CLI the profile chose" do
      expect(dispatcher.adapter_for(job).name).to eq("codex")
    end
  end

  context "when the agent has named its session" do
    before { job.handle.session = "sess-1" }

    it "shows it on the agent's row" do
      expect(dispatcher.board.rows.first.session).to eq("sess-1")
    end
  end

  context "when a compaction stopped the agent and then could not happen" do
    let!(:first) { job }

    before do
      dispatcher.compact(first.key).refuse!("could not compact", restart: true)
      executor.release_all(1)
      first.thread.join(2)
      start_agents
    end

    it "starts it again, in the same round" do
      expect([executor.calls.count(first.key), dispatcher.running.first.task.round]).to eq([2, 1])
    end
  end
end
