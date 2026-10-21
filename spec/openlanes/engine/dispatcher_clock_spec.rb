# frozen_string_literal: true

require_relative "../live/live_context"

# The dispatcher reads time from the clock it was given, so a spec moves
# time instead of waiting for it.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  subject(:timed) { described_class.new(runner:, clock:) }

  include_context "with a live run"

  let(:clock) { OpenLanes::Clock::Fake.new(now: Time.utc(2026, 10, 20, 12)) }
  let(:subject_plan) { tree.subjects.find { it.feature.ordinal.to_s == "001.00" } }

  before { building("001.00", "tax-rule-dsl") }

  it "stamps a finished plan with the fake clock's time, after the clock moves" do
    clock.advance(3600)
    timed.send(:finish, subject_plan, "approved")
    expect(OpenLanes::Plans::PlanState.for(subject_plan.feature.path).finished.at).to eq(Time.utc(2026, 10, 20, 13))
  end

  it "waits on the clock when no sleeper is given, so a tick's second passes at once" do
    timed.instance_variable_get(:@sleeper).call(1)
    expect(clock.monotonic).to eq(1.0)
  end

  it "still honours a sleeper given beside the clock" do
    waits = []
    described_class.new(runner:, clock:, sleeper: ->(s) { waits << s }).instance_variable_get(:@sleeper).call(1)
    expect([waits, clock.monotonic]).to eq([[1], 0.0])
  end
end
