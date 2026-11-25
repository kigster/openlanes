# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Launcher do
  subject(:launcher) { described_class.new(spawn:) }

  let(:started) { [] }
  let(:spawn) { ->(argv, chdir:, **) { (started << [argv, chdir]) && child } }
  let(:child) { instance_double(OpenLanes::Execution::Child, pid: 4242) }
  let(:traces) { Dir.mktmpdir("launcher-traces") }
  let(:handle) { OpenLanes::Execution::Executor::Handle.new }
  let(:sessions) { OpenLanes::Execution::Executor::Sessions.new }
  let(:profile) { OpenLanes::Agents::Profile.new(adapter: OpenLanes::Adapters.for("claude"), model: "opus", effort: "high") }
  let(:attempt) do
    OpenLanes::Execution::Executor::Attempt.new(agent: nil,
      subject: nil,
      root: "/repo",
      profile:,
      trace: File.join(traces, "t.ndjson"),
      handle:,
      sessions:)
  end

  after { FileUtils.rm_rf(traces) }

  it "starts the argv in the attempt's checkout" do
    launcher.launch(%w[claude -p x], attempt)
    expect(started).to eq([[%w[claude -p x], "/repo"]])
  end

  # The engine claims the plan folder in alock first; without a parent
  # every `acquire` the agent made inside it was refused.
  it "names the engine as the agent's alock parent, beside the adapter's own variables" do
    envs = []
    recording = ->(_argv, env:, **) { (envs << env) && child }
    described_class.new(spawn: recording).launch(%w[claude -p x], attempt)
    expect(envs.first).to include(profile.adapter.environment).and include("AGENT_PARENT_ID" => OpenLanes::Engine::AgentLocks.holder)
  end

  it "hands the handle the process and the sessions its transcript" do
    launcher.launch(%w[claude], attempt)
    expect([handle.child, sessions.current.pid]).to eq([child, 4242])
  end

  it "reports a process a restarted engine can take back" do
    fields = []
    handle.on_restart = ->(given) { fields << given.keys }
    launcher.follow(instance_double(OpenLanes::Execution::AgentProcess, pid: 4242, restart: { pid: 4242 }), attempt)
    expect(fields).to eq([[:process]])
  end

  it "arms a clock and hands it to the handle" do
    clock = launcher.start_clock(handle, seconds: 60)
    expect(handle.clock).to equal(clock)
  ensure
    clock&.stop
  end

  it "gives a reattached agent that had barely begun its whole budget" do
    allow(OpenLanes::Execution::ProcessStart).to receive(:of).and_return(nil)
    restart = { "deadline" => (Time.now + 30).utc.iso8601, "process" => { "pid" => 1 } }
    expect(launcher.rearm(OpenLanes::Agents.find("backend-coder"), restart, budget: 900)).to be_between(1, 900)
  end
end
