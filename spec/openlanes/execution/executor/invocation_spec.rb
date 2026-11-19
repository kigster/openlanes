# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Invocation do
  subject(:invocation) { described_class.new(lean: true, trace_dir: traces) }

  let(:traces) { Dir.mktmpdir("invocation-traces") }
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:plan) { Struct.new(:feature).new(Struct.new(:ordinal, :path).new("001.00", "/plans/001.00")) }
  let(:profile) { OpenLanes::Agents::Profile.new(adapter: OpenLanes::Adapters.for("claude"), model: "opus", effort: "high") }
  let(:attempt) do
    OpenLanes::Execution::Executor::Attempt.new(agent:, subject: plan, root: "/repo", profile:, trace: nil, handle: nil, sessions: nil)
  end

  after { FileUtils.rm_rf(traces) }

  def pairs(argv) = argv.each_cons(2).to_a

  it "starts the profile's model with the prompt" do
    expect(pairs(invocation.argv(attempt, prompt: "Build it."))).to include(["-p", "Build it."], ["--model", "opus"])
  end

  it "withholds every forbidden command from an agent not granted it" do
    argv = invocation.argv(attempt, prompt: "x")
    expect(argv.join(" ")).to include("Bash(git push:*)", "Bash(git commit:*)")
  end

  it "carries a session on when given one" do
    expect(pairs(invocation.argv(attempt, prompt: "x", resume: "sess-1"))).to include(["--resume", "sess-1"])
  end

  it "names a trace for the plan and the agent under its directory" do
    expect(invocation.trace_path(agent, plan)).to start_with(traces).and include("-001.00-backend-coder-").and end_with(".ndjson")
  end

  it "names two traces apart" do
    expect(invocation.trace_path(agent, plan)).not_to eq(invocation.trace_path(agent, plan))
  end
end
