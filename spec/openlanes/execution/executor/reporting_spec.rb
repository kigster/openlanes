# frozen_string_literal: true

# The executor's answers about how an invocation went, each of which lives in
# Verdict or Said. Public before the cut, so still answered by the executor.
RSpec.describe OpenLanes::Execution::Executor::Reporting do
  subject(:executor) { OpenLanes::Execution::Executor.new(root: Dir.pwd, spawn: ->(*) {}, max_tokens: 500) }

  let(:transcript) { instance_double(OpenLanes::Execution::Transcript, failed?: false, error: nil, plain: ["Nearly there."]) }
  let(:sessions) do
    instance_double(OpenLanes::Execution::Executor::Sessions,
      current:   transcript,
      up:        10,
      down:      2,
      spawned:   1,
      delegated: 0,
      cached:    3,
      tools:     4)
  end
  let(:started) { OpenLanes::UI.monotonic }

  it "reports what an invocation spent" do
    expect(executor.spent(sessions, started, ok: true, note: "completed").to_h.slice(:ok, :note, :up, :down, :subagents, :cached))
      .to eq(ok: true, note: "completed", up: 10, down: 2, subagents: 1, cached: 3)
  end

  it "reports a failure with its note and what it spent" do
    result = executor.failure(sessions, started, "exited 3", killed: :key)
    expect(result.to_h.slice(:ok, :note, :up, :killed)).to eq(ok: false, note: "exited 3", up: 10, killed: :key)
  end

  it "quotes what the agent said last" do
    expect(executor.said(transcript)).to eq(OpenLanes::Execution::Executor::Said.of(transcript))
    expect(executor.said(transcript)).to eq("Nearly there.")
  end

  it "words a kill as Verdict does, with or without the clock it once took" do
    verdict = OpenLanes::Execution::Executor::Verdict.new(max_tokens: 500)
    expect([executor.killed_note(:timeout), executor.killed_note(:budget, :clock)])
      .to eq([verdict.killed_note(:timeout), verdict.killed_note(:budget)])
  end
end
