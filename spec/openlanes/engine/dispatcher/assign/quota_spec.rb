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

  it "refuses an agent already running on the plan" do
    desk.running << job_for(plan, coder)
    expect(quota.eligible?(coder, plan)).to be(false)
  end

  it "refuses an agent that has used every round it had" do
    coder.rounds.times { desk.remember("001.00", coder.name, plan.status.key, "Interrupted", it + 1) }
    expect(quota.eligible?(coder, plan)).to be(false)
  end
end
