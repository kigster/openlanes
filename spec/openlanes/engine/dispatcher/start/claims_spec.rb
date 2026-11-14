# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Start::Claims, :tree do
  subject(:holds) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  it "reserves a free plan" do
    expect(holds.reserve("001.00", plan, coder)).to be(true)
  end

  it "refuses a plan held in alock, and remembers the refusal" do
    allow(desk.locks).to receive(:reserve).and_raise(OpenLanes::Engine::PlanLocks::Refused, "001.00 is held in alock")
    allow(runner).to receive(:release)
    expect([holds.reserve("001.00", plan, coder), desk.refusals.to_a]).to eq([false, ["001.00"]])
  end

  it "says the lock was lost when another run holds it" do
    allow(desk.locks).to receive(:hold).and_raise(OpenLanes::Plans::Lock::Held, "held by pid 1")
    allow(OpenLanes::UI).to receive(:log)
    expect(holds.lock("001.00", plan)).to be(false)
  end
end
