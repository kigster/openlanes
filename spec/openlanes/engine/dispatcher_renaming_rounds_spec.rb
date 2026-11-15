# frozen_string_literal: true

require_relative "round_engine_context"

# Issue 255, finding 1: an agent that `starts_as` renames the folder as its
# round starts, so the plan is picked up in one state (📋 Planned) and worked
# in the next (🟡 Building). The round has to be counted for the second.
# Counted for the first, a restarted engine found no round spent on Building
# and told the agent round 1 again.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a restartable engine"

  let(:agent_name) { "coder" }
  let(:agent_front) do
    "handles: [planned, building]\nadvances_to: ready_for_review\nstarts_as: building\nrounds: 3\nadapter: claude\nledger: [plan.md]"
  end

  before { plans { |t| t.plan "001.00", :planned, "carry-on", files: { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## Unit 1\n" } } }

  it "records the state the round works in beside the one the plan was picked up in" do
    engine(rounds: 1)

    expect(stages.map { it.values_at("round", "from", "state", "visit") }).to eq([[1, "planned", "building", 1]])
  end

  context "when the engine is stopped after the round that renamed the folder" do
    before { engine(rounds: 1) }

    it "tells the agent rounds 2 and 3 after the restart, not round 1 again" do
      first = told.dup
      engine

      expect([first, told.drop(first.size)]).to eq([[1], [2, 3]])
    end

    it "never writes two stages under one round number, or more than the agent's rounds" do
      engine

      expect(stages.map { it["round"] }).to eq([1, 2, 3])
    end

    it "hands out nothing more once a second restart finds every round spent" do
      engine
      engine

      expect(told).to eq([1, 2, 3])
    end
  end

  context "when the start that renamed the folder spends nothing" do
    let(:note) { "exited 1 before the first token" }
    let(:spent) { 0 }

    it "backs off: an engine started inside the wait starts nothing" do
      2.times { engine }

      expect([told, stages.map { it["status"] }]).to eq([[1], ["Failed start"]])
    end

    it "names the agent that is backing off in the idle line" do
      engine

      expect(idle_line).to include("failed starts: 001.00 coder (retrying after a backoff)")
    end

    it "stops after three in a row, and asks a person once" do
      [0, 31, 61, 121, 241].each do |wait|
        clock.advance(wait)
        engine
      end

      expect([told, plan_state.extensions.map { it.values_at("agent", "state") }]).to eq([[1, 1, 1], [%w[coder building]]])
    end
  end
end
