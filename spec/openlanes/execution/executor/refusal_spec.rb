# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Refusal do
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:confined) { agent.with(confined_to: %w[spec.md]) }

  def profile(adapter) = OpenLanes::Agents::Profile.new(adapter: OpenLanes::Adapters.for(adapter), model: nil, effort: nil)

  it "answers a dry run without spending anything" do
    expect(described_class.dry_run(agent).to_h.slice(:ok, :note, :up, :seconds))
      .to eq(ok: true, note: "dry run - would invoke backend-coder", up: 0, seconds: 0.0)
  end

  it "lets an unconfined agent start" do
    expect(described_class.unconfinable(agent, profile("claude"))).to be_nil
  end

  it "lets a confined agent start on a CLI that can confine it" do
    expect(described_class.unconfinable(confined, profile("claude"))).to be_nil
  end

  it "refuses a confined agent on a CLI that cannot confine it" do
    unconfining = OpenLanes::Adapters.names.map { OpenLanes::Adapters.for(it) }.find { !it.confines? }
    skip "every adapter confines" unless unconfining
    refused = described_class.unconfinable(confined, profile(unconfining.name))
    expect([refused.ok, refused.note]).to eq([false, "backend-coder is confined to spec.md, and #{unconfining.executable} cannot enforce that"])
  end
end
