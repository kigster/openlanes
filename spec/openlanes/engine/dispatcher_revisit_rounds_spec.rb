# frozen_string_literal: true

require_relative "round_engine_context"

# Issue 255, finding 4: a plan that comes back to a state it has been in
# (a rejection, an unblock) starts its rounds there again at 1. A request for
# more rounds is about one visit, so the second visit raises its own. Found
# by agent, state and round alone, the first visit's request for "round 1"
# stood in for it, and the plan parked with nobody asked.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a restartable engine"

  let(:agent_front) { "handles: [new]\nadvances_to: researched\nrounds: 1\nadapter: claude\nledger: [spec.md]" }
  let(:requests) { plan_state.extensions.map { it.values_at("number", "round", "moves", "closed") } }
  let(:questions) { OpenLanes::Engine::Extensions.questions(tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")), plan_state) }

  # Away and back: two moves, as a rejection or an unblock makes.
  def revisit
    plan_state.state!(:researched)
    plan_state.state!(:new)
  end

  before do
    plans { |t| t.plan "001.00", :new, "carry-on", files: { "spec.md" => spec_body } }
    engine
  end

  it "asks for a round once the agent has used its own on the first visit" do
    expect(requests).to eq([[1, 1, 0, nil]])
  end

  context "when the first visit's request was closed and the plan comes back" do
    before do
      plan_state.settle_extension!(1, closed: "finished", at: clock.now)
      revisit
      told.clear
      engine
    end

    it "starts the agent again at round 1" do
      expect(told).to eq([1])
    end

    it "raises the second visit's own request" do
      expect(requests).to eq([[1, 1, 0, "finished"], [2, 1, 2, nil]])
    end

    it "asks once: a restart on the same visit raises nothing more" do
      engine

      expect([told, requests.size]).to eq([[1], 2])
    end
  end

  context "when the first visit's request is still open as the plan comes back" do
    before do
      revisit
      engine
    end

    it "raises a request for the new visit beside it" do
      expect(requests).to eq([[1, 1, 0, nil], [2, 1, 2, nil]])
    end

    it "shows only the new visit's request" do
      expect(questions.map { it[:number] }).to eq([2])
    end

    it "grants nothing for the old one, and closes it" do
      granted = extensions.answer!(folder, 1, "a", by: "dana")

      expect([granted, extensions.rounds(folder, "researcher", :new), requests.first.last]).to eq([nil, 0, "the plan moved on"])
    end

    it "grants the new visit's round for the new one" do
      extensions.answer!(folder, 2, "a", by: "dana")
      told.clear
      engine

      expect([extensions.rounds(folder, "researcher", :new), told]).to eq([1, [2]])
    end
  end
end
