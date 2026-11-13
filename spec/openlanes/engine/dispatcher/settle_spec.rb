# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Settle, :tree do
  subject(:settle) { described_class.new(desk, rename:, poll:, row: rows.method(:row_for)) }

  include_context "with a dispatcher desk"

  let(:rename) { OpenLanes::Engine::Dispatcher::Rename.new(desk) }
  let(:poll) { OpenLanes::Engine::Dispatcher::Poll.new(desk) }
  let(:rows) { OpenLanes::Engine::Dispatcher::Rows.new(desk, waiting_on: -> { {} }) }
  let(:handle) { OpenLanes::Execution::Executor::Handle.new }
  let(:crashed) do
    job_for(plan,
      coder,
      handle:,
      up: 0,
      down: 0,
      started_at: OpenLanes::UI.monotonic,
      thread: Thread.new { nil }.tap(&:join),
      result: RuntimeError.new("boom\nand a backtrace"))
  end

  it "reaps nothing while every job is still at work" do
    desk.running << job_for(plan, coder, handle:, thread: Thread.current)
    expect([settle.reap, desk.running.size]).to eq([[], 1])
  end

  it "makes a failed attempt of a job whose thread raised, and keeps its row on the screen" do
    desk.running << crashed
    settle.reap
    attempt = desk.attempts.first
    expect([desk.running, attempt.ok, attempt.note, desk.recent.first[:row].state]).to eq([[], false, "boom", :failed])
  end

  it "records the crashed round as Interrupted, so the agent may run it again" do
    desk.running << crashed
    settle.reap
    expect(desk.history[["001.00", coder.name]]).to eq([{ state: :building, status: "Interrupted", round: 1 }])
  end

  it "drops the model labels a review round's replacements used" do
    replacing = Class.new(HeldExecutor) { def end_replacements(_ordinal) = nil }.new(traces)
    allow(runner).to receive(:executor).and_return(replacing)
    desk.models[["001.00", "staff-reviewer"]] = "opus"
    settle.end_replacements("001.00")
    expect(desk.models).to be_empty
  end
end
