# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Arbitration, :tree do
  before { plans { |t| t.plan "014.00", :verifying, "capped", files: { "spec.md" => spec_body } } }

  it "only says the plan is at the cap, until plan 015's arbitrator exists" do
    allow(OpenLanes::UI).to receive(:log)
    plan = OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first

    described_class.new.call(plan:, count: 2, max: 2)

    expect(OpenLanes::UI).to have_received(:log).with(/rejected 2 of 2: at the cap.*plan 015/, level: :warn, plan: "014.00")
  end
end
