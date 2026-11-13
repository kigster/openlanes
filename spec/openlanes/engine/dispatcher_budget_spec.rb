# frozen_string_literal: true

require_relative "../live/live_context"

# 062.00 B4: a plan past `budget.plan_usd` gets no new agent. It is held, as
# a queued plan is, and a run whose only plans are over the cap stops.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  def finished(ordinal, cost)
    OpenLanes::Events::Event.new(event_id: "e-#{ordinal}-#{cost}",
      kind: "agent_finished",
      at: Time.now,
      plan: ordinal,
      agent: "backend-coder",
      payload: { "round" => 1, "status" => "Completed", "cost_usd" => cost })
  end

  let(:spent) { [finished("001.00", 6.0), finished("002.00", 1.0)] }
  let(:budget) { OpenLanes::Engine::Budget.new(cap: -> { 5.0 }, events: -> { spent }) }
  let(:dispatcher) { described_class.new(runner:, sleeper: ->(_) {}, budget:) }

  context "with one plan over the cap and one under it" do
    before do
      building("001.00", "spendy")
      building("002.00", "thrifty")
    end

    it "starts an agent on the plan under the cap, and none on the one over it" do
      start_agents
      expect(executor.calls.map { it.split("/").first }.uniq).to eq(%w[002.00])
      executor.release_all
      dispatcher.running.each { it.thread.join(2) }
    end

    it "fires no state and renames no folder on the held plan" do
      start_agents
      expect(tree.reload.find("001.00").status.key).to eq(:building)
      executor.release_all
      dispatcher.running.each { it.thread.join(2) }
    end
  end

  context "with only over-cap plans" do
    let(:spent) { [finished("001.00", 6.0)] }

    before { building("001.00", "spendy") }

    it "reaches a fixed point, saying why" do
      3.times { dispatcher.tick }
      expect([executor.calls, dispatcher.done?]).to eq([[], true])
      expect(dispatcher.send(:idle_reason, tree.reload.subjects)).to include("held by budget: 001.00 over budget: $6.00 of $5.00")
    end
  end
end
