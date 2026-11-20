# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Assign::Quota, :tree do
  subject(:quota) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  it "lets an agent with no rounds on the state take one" do
    expect(quota.eligible?(coder, plan)).to be(true)
  end

  it "refuses an agent that completed the state" do
    desk.remember("001.00", coder.name, plan.status.key, "Completed", 1)
    expect(quota.eligible?(coder, plan)).to be(false)
  end

  # C13: an agent on another plan is waiting out a rate limit on this
  # agent's CLI, so nobody new starts on it until the wait ends.
  it "refuses an agent whose adapter is paused for a rate limit, spending no round" do
    desk.adapter_pause.hold(OpenLanes::Agents::Profile.resolve(coder).adapter.name, 120)

    expect([quota.eligible?(coder, plan), desk.past_rounds(plan, coder)]).to eq([false, []])
  end

  it "lets an agent on another adapter start while one adapter is paused" do
    desk.adapter_pause.hold("some-other-cli", 120)
    expect(quota.eligible?(coder, plan)).to be(true)
  end

  it "refuses an agent already running on the plan" do
    desk.running << job_for(plan, coder)
    expect(quota.eligible?(coder, plan)).to be(false)
  end

  describe "#ask_for_rounds" do
    let(:requests) { OpenLanes::Plans::PlanState.for(plan.feature.path).extensions.map { it.values_at("agent", "round") } }

    before { coder.rounds.times { desk.remember("001.00", coder.name, plan.status.key, "Interrupted", it + 1) } }

    it "asks for an agent that used every round it had without finishing" do
      quota.ask_for_rounds

      expect(requests).to eq([[coder.name, coder.rounds]])
    end

    it "asks nothing for an agent that finished" do
      desk.remember("001.00", coder.name, plan.status.key, "Completed", coder.rounds)
      quota.ask_for_rounds

      expect(requests).to eq([])
    end

    # A Started round with no job is nobody's: skipped as a running one is,
    # its agent sat at its budget and no one was asked.
    it "asks for an agent whose last round is still Started with no job running it" do
      desk.remember("001.00", coder.name, plan.status.key, "Started", coder.rounds)
      quota.ask_for_rounds

      expect(requests).to eq([[coder.name, coder.rounds]])
    end
  end

  it "refuses an agent that has used every round it had" do
    coder.rounds.times { desk.remember("001.00", coder.name, plan.status.key, "Interrupted", it + 1) }
    expect(quota.eligible?(coder, plan)).to be(false)
  end
end
