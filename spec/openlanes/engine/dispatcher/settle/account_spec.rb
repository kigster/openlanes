# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Settle::Account, :tree do
  subject(:account) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  let(:result) { OpenLanes::Execution::Executor::Result.new(ok: true, note: "done", up: 10, down: 2, subagents: 1, delegated: 0, seconds: 1.5) }
  let(:job) { job_for(plan, coder, round: 2, result:, status: "Completed") }

  it "takes the round as the executor left it" do
    attempt = account.call(job)
    expect([attempt.ordinal, attempt.agent, attempt.ok, attempt.note, attempt.up, attempt.round, attempt.status])
      .to eq(["001.00", "backend-coder", true, "done", 10, 2, "Completed"])
  end

  it "counts a round that ended in an exception as failed, saying and spending nothing" do
    attempt = account.call(job_for(plan, coder, result: RuntimeError.new("boom")))
    expect([attempt.ok, attempt.note, attempt.up, attempt.from, attempt.to]).to eq([false, "", 0, :building, :building])
  end
end
