# frozen_string_literal: true

require_relative "../live/live_context"

# Plan 035, spec item 3: while `.openlanes.yml` has no
# `desired_codebase_quality:`, no agent starts. The question goes on the
# first plan in scope, once, and the answer lifts the gate.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  before do
    building("001.00", "first")
    building("002.00", "second")
  end

  let(:unset) { [true] }

  let(:runner) do
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :shared,
      claims:,
      sleeper: ->(_) {},
      quality_gate: -> { unset.first })
  end

  def asks = OpenLanes::Engine::QualityQuestion

  it "starts nobody and asks once, on the first plan, while the key is missing" do
    2.times { dispatcher.tick }

    aggregate_failures do
      expect(dispatcher.running).to be_empty
      expect(executor.calls).to be_empty
      expect(asks.open_in(tree.dir)).to eq(path_of("001.00"))
      expect(asks.questions(tree.reload.find("002.00"), OpenLanes::Plans::PlanState.for(path_of("002.00")))).to be_empty
      expect(dispatcher).to be_done
    end
  end

  it "starts work once the key is there" do
    dispatcher.tick
    unset[0] = false
    dispatcher.tick

    expect(dispatcher.running).not_to be_empty
  end

  it "runs ungated when the runner is given no gate" do
    ungated = OpenLanes::Engine::Runner.new(tree:, executor:, agents:, isolation: :shared, claims:, sleeper: ->(_) {})
    expect(ungated).not_to be_awaiting_quality
  end
end
