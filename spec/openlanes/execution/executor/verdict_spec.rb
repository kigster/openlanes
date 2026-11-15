# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Verdict do
  subject(:verdict) { described_class.new(max_tokens: 500) }

  let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:broken) { instance_double(Process::Status, success?: false, exitstatus: 3) }
  let(:handle) { OpenLanes::Execution::Executor::Handle.new }
  let(:transcript) { instance_double(OpenLanes::Execution::Transcript, failed?: false, error: nil, plain: ["Oops."], activity: "editing") }
  let(:sessions) do
    instance_double(OpenLanes::Execution::Executor::Sessions,
      current:   transcript,
      up:        10,
      down:      2,
      spawned:   0,
      delegated: 0,
      cached:    1,
      tools:     4)
  end
  let(:profile) { OpenLanes::Agents::Profile.new(adapter: OpenLanes::Adapters.for("claude"), model: "opus", effort: "high") }
  let(:attempt) do
    OpenLanes::Execution::Executor::Attempt.new(agent: nil, subject: nil, root: "/r", profile:, trace: "/t.ndjson", handle:, sessions:)
  end
  let(:before) { instance_double(OpenLanes::Execution::Boundary::Snapshot, violation: violation) }
  let(:violation) { nil }

  def judged(status = ok) = verdict.judge(attempt, status, before:, started: OpenLanes::UI.monotonic)

  it "calls a clean run completed, with its tool calls" do
    expect(judged.to_h.slice(:ok, :note, :up, :cached)).to eq(ok: true, note: "completed - 4 tool calls", up: 10, cached: 1)
  end

  it "names the exit and what the agent said last" do
    expect(judged(broken).note).to eq("claude exited 3: Oops. - trace: /t.ndjson")
  end

  context "when the agent moved what it must not" do
    let(:violation) { "HEAD moved" }

    it "fails it on the boundary" do
      expect(judged.to_h.slice(:ok, :note)).to eq(ok: false, note: "HEAD moved")
    end
  end

  it "reports a limit that never lifted ahead of the CLI's words" do
    handle.throttled = "rate limited: gave up"
    expect(judged(broken).to_h.slice(:throttled, :note)).to eq(throttled: true, note: "rate limited: gave up - trace: /t.ndjson")
  end

  it "says why a killed agent was killed and what it was doing" do
    handle.kill!(grace: 0, reason: :budget)
    expect(judged.to_h.slice(:killed, :note))
      .to eq(killed: :budget, note: "token budget of 500 exceeded, last seen editing - trace: /t.ndjson")
  end

  it "names a kill by request" do
    expect(verdict.killed_note(:key)).to eq("killed by request")
  end
end
