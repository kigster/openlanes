# frozen_string_literal: true

# Decision C11: a dollar cap the event log cannot count refuses the run.
RSpec.describe OpenLanes::Engine::Budget::Guard do
  let(:off) { OpenLanes::Events::NullSink.new }
  let(:on) { instance_double(OpenLanes::Events::Sink, enabled?: true) }

  it "refuses a cap with the event log off, and says how to fix it" do
    expect(described_class.new(cap: 25.0, events: off).refusal).to eq(
      "budget.plan_usd is $25 but events.enabled is false, so spend cannot be counted " \
      "and the cap would never hold a plan.\n\nEnable events in .openlanes/config.yml, or remove the cap."
    )
  end

  it "names a cap with cents to the cent" do
    expect(described_class.new(cap: 2.5, events: off).refusal).to start_with("budget.plan_usd is $2.50 but")
  end

  it "lets a cap with the log on through" do
    expect(described_class.new(cap: 25.0, events: on).refusal).to be_nil
  end

  it "lets a run with no cap through, log or not" do
    expect(described_class.new(cap: nil, events: off).refusal).to be_nil
  end
end
