# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Result do
  def result(**overrides)
    described_class.new(ok: false,
      note: "claude exited 1: OAuth session expired",
      up: 0,
      down: 0,
      subagents: 0,
      delegated: 0,
      seconds: 2.0,
**overrides)
  end

  it "classifies a two-second OAuth session expired exit as a failed authentication start" do
    expect([result.failed_start?, result.auth_failure?]).to eq([true, true])
  end

  it "names the authentication failure in the CLI's own words, without the exit code" do
    expect([result(note: "claude exited 1: OAuth session expired - trace: /tmp/x.ndjson").auth_reason,
            result(note: "claude exited 1: segmentation fault").auth_reason]).to eq(["OAuth session expired", nil])
  end

  it "classifies a start that spent nothing for another reason as a failed start, not an auth failure" do
    other = result(note: "claude exited 1: segmentation fault")
    expect([other.failed_start?, other.auth_failure?]).to eq([true, false])
  end

  it "treats a killed run as a real failure" do
    expect(result(killed: :timeout).failed_start?).to be(false)
  end

  it "treats a run that spent tokens as a real failure" do
    expect(result(up: 12, down: 3).failed_start?).to be(false)
  end

  it "treats a run that made a tool call as a real failure" do
    expect(result(tools: 1).auth_failure?).to be(false)
  end

  it "treats a throttled run as no failed start" do
    expect(result(throttled: true).failed_start?).to be(false)
  end

  it "never calls a success a failed start" do
    expect(result(ok: true).failed_start?).to be(false)
  end

  it "recognises each CLI's own sign-in refusal" do
    notes = ["Not logged in · Please run /login", "Error authenticating: bad token", "Invalid API key", "401 Unauthorized"]
    expect(notes.map { result(note: it).auth_failure? }).to all(be(true))
  end
end
