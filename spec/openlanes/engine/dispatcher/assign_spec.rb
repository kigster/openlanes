# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Assign, :tree do
  subject(:assign) { described_class.new(desk, start:, rescan: 3) }

  include_context "with a dispatcher desk"

  let(:start) { instance_double(OpenLanes::Engine::Dispatcher::Start, start: true) }

  it "offers the building plan to an agent that handles it" do
    agent, subject = assign.next_dispatchable
    expect([agent.handles?(subject.status), subject.feature.ordinal.to_s]).to eq([true, "001.00"])
  end

  it "offers nothing on a plan this run has finished with" do
    desk.finished_plans << "001.00"
    expect(assign.next_dispatchable).to be_nil
  end

  it "starts what it picked, on a pass that begins with no refusals left over" do
    started = []
    desk.refusals << "stale"
    allow(start).to receive(:start) { |_agent, subject| desk.finished_plans << (started << subject.feature.ordinal.to_s).last }
    assign.dispatch
    expect([started, desk.refusals.to_a]).to eq([["001.00"], []])
  end

  it "never rests unless the run stays" do
    desk.idle = true
    expect(assign.resting?).to be(false)
  end

  context "when the run stays and is idle" do
    let(:stay) { true }

    before { desk.idle = true }

    it "rests until the rescan interval has passed" do
      expect(Array.new(4) { assign.resting? }).to eq([true, true, false, true])
    end

    it "looks again at once when woken" do
      desk.wake!
      expect([assign.resting?, desk.wake]).to eq([false, false])
    end
  end
end
