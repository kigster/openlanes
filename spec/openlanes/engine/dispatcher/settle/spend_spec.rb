# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Dispatcher::Settle::Spend do
  it "reads what an executor result spent" do
    result = OpenLanes::Execution::Executor::Result.new(ok: true, note: "done", up: 10, down: 2, subagents: 1, delegated: 0, seconds: 1.5)
    expect(described_class.of(result).to_h).to eq(up: 10, down: 2, subagents: 1, delegated: 0, seconds: 1.5)
  end

  it "counts nothing spent by a result that cannot say, such as an exception" do
    expect(described_class.of(RuntimeError.new("boom")).to_h).to eq(up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0)
  end
end
