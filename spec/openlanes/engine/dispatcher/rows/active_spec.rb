# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Rows::Active, :tree do
  subject(:active) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  let(:handle) { OpenLanes::Execution::Executor::Handle.new }
  let(:job) { job_for(plan, coder, handle:, up: 12, down: 3, started_at: OpenLanes::UI.monotonic, message: "reading") }

  it "draws a running job's row with what it spent and said" do
    row = active.call(job)
    expect([row.ordinal, row.agent, row.state, row.up, row.down, row.message]).to eq(["001.00", "backend-coder", :running, 12, 3, "reading"])
  end

  it "moves the job's spinner on a frame each time it is drawn" do
    2.times { active.call(job) }
    expect(job.frame).to eq(2)
  end

  it "names the ledger file the agent writes before it has written one" do
    expect(active.call(job).file).to eq(coder.ledger.first.to_s)
  end
end
