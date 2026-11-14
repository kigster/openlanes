# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Desk::Events, :tree do
  subject(:events) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  let(:job) { job_for(plan, coder, round: 2) }

  it "names the adapter the agent's profile resolves to" do
    expect(events.adapter_for(job)).to equal(desk.adapter_of(coder, plan))
  end

  it "carries the plan, round, agent, adapter and model on every event" do
    desk.invocations[job.key] = 12.5
    expect(events.event_fields(job)).to eq(plan: "001.00",
      round: 2,
      agent: "backend-coder",
      invocation_start: 12.5,
      adapter: desk.adapter_of(coder, plan).name.to_s,
      model: desk.model_for(coder, plan, root: plans_root))
  end

  it "leaves the invocation start empty for a job not yet invoked" do
    expect(events.event_fields(job)[:invocation_start]).to be_nil
  end

  # An event is still worth logging when the profile cannot be resolved, so
  # the name alone goes missing and the event keeps its other fields.
  it "reports no adapter name when the profile cannot be resolved" do
    allow(desk).to receive(:adapter_of).and_raise(OpenLanes::Error, "no such adapter")
    expect(events.adapter_name(job)).to be_nil
  end
end
