# frozen_string_literal: true

# Plan 041, PR 2: an engine that died left an agent running under its agent
# supervisor. The next engine finds it in the state file, takes it back and
# settles its round, and the agent CLI is never started a second time.
#
# The dead engine is played by hand: its state file names a pid that is
# gone, and the agent it started is a real `openlanes-agent` running a fake
# `claude` from a temp bin. A real Runner is the engine that comes back.
RSpec.describe "reattaching to an agent a dead engine left", :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:root) { File.dirname(plans_root) }
  let(:agents_dir) { Dir.mktmpdir }
  let(:agents) do
    File.write(File.join(agents_dir, "researcher.md"),
      "---\nname: researcher\nhandles: [new]\nadvances_to: researched\nrounds: 1\n" \
      "adapter: claude\nledger: [spec.md]\n---\nbody")
    OpenLanes::Agents::Registry.new(dir: agents_dir)
  end
  let(:bin) { Dir.mktmpdir("openlanes-reattach") }
  let(:traces) { File.join(bin, "traces") }
  let(:starts) { File.join(bin, "starts.log") }
  let(:release) { File.join(bin, "release") }
  let(:state_path) { File.join(bin, "state.json") }
  let(:dead_pid) { Process.spawn("true").tap { Process.wait(it) } }
  let(:heard) { [] }
  let!(:tap) { OpenLanes::UI.tap_log(->(message, _) { heard << message }) }
  let(:stage) { JSON.parse(File.read(state_path)).dig("plans", "001.00", "stages").first }
  let(:started) { File.readlines(starts).size }
  let(:died) { OpenLanes::Engine::Recovery::DIED }

  # The real agent supervisor, PATH pointed at the fake: see
  # resume_across_rounds_spec.rb for why ENV would not reach it.
  let(:starter) { OpenLanes::Execution::AgentProcess.spawner(dir: traces, root:) }
  let(:spawn) do
    lambda { |argv, chdir:, env:, label:|
      starter.call(argv, chdir:, env: env.merge("PATH" => "#{bin}:/usr/bin:/bin"), label:)
    }
  end

  # A `claude` that notes each start and waits to be released, then
  # succeeds. It also gives up once the temp bin is gone, so none outlives
  # the example.
  let(:fake_claude) do
    <<~SH
      #!/bin/sh
      echo start >> '#{starts}'
      while [ ! -f '#{release}' ] && [ -d '#{bin}' ]; do sleep 0.02; done
      echo '{"type":"system","subtype":"init","session_id":"sess-1"}'
      echo '{"type":"result","subtype":"success","is_error":false,"result":"done","session_id":"sess-1","usage":{"input_tokens":10,"output_tokens":5}}'
    SH
  end

  # What the dead engine's executor had started.
  let(:agent_process) do
    spawn.call(["claude", "-p", "hi"],
      chdir: root,
      env:   {},
      label: OpenLanes::Execution::AgentProcess::Label.new(plan: "001.00", agent: "researcher"))
  end

  # What the dead engine's executor recorded for the agent it started.
  let(:restart) do
    { process:  agent_process.restart,
      cwd:      root,
      trace:    File.join(traces, "001.00-researcher.ndjson"),
      control:  File.join(traces, "001.00-researcher.control"),
      before:   OpenLanes::Execution::Boundary.snapshot(root).to_h,
      deadline: (Time.now + 600).utc.iso8601 }
  end

  # The dead engine: a Started stage, and its restart context.
  def dead_engine
    state = OpenLanes::Engine::StateFile.new(path: state_path, pid: dead_pid)
    state.begin_run!(root:)
    state.record("001.00", agent: "researcher", round: 1, status: "Started", state: "new")
    state.restart("001.00", agent: "researcher", round: 1, **restart)
    OpenLanes::Execution::AgentProcess.forget(agent_process)
    sleep(0.02) until File.exist?(starts)
  end

  def engine
    OpenLanes::Engine::Runner.new(tree:,
      executor: OpenLanes::Execution::Executor.new(root:, spawn:, trace_dir: traces),
      agents:,
      state: OpenLanes::Engine::StateFile.new(path: state_path),
      isolation: :shared,
      jobs: 1,
      sleeper: ->(_) { File.write(release, "") },
      extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false)).call
  end

  before do
    FileUtils.mkdir_p(traces)
    File.write(File.join(bin, "claude"), fake_claude)
    File.chmod(0o755, File.join(bin, "claude"))
    plans { |t| t.plan "001.00", :new, "carry-on", files: { "spec.md" => spec_body } }
  end

  after do
    OpenLanes::UI.untap_log(tap)
    FileUtils.rm_rf([agents_dir, bin])
  end

  context "with the agent still running" do
    let!(:attempts) do
      dead_engine
      engine
    end

    it("takes it back") { expect(heard).to include("reattached") }
    it("never starts it again") { expect(started).to eq(1) }
    it("settles its round from what the agent wrote") { expect(stage.values_at("session", "up", "down")).to eq(["sess-1", 10, 5]) }
    it("is not counted stranded") { expect(stage["exit"]).not_to eq(died) }
    it("ends one attempt") { expect(attempts.map(&:agent)).to eq(["researcher"]) }
  end

  context "with the agent ended while no engine ran" do
    before do
      dead_engine
      File.write(release, "")
      sleep(0.02) until File.exist?(agent_process.restart[:status])
      engine
    end

    it("settles it from what the agent wrote") { expect(stage.values_at("session", "up", "down")).to eq(["sess-1", 10, 5]) }
    it("is not counted stranded") { expect(stage["exit"]).not_to eq(died) }
    it("never starts it again") { expect(started).to eq(1) }
  end

  context "with an agent supervisor that died with the engine" do
    before do
      dead_engine
      Process.kill("KILL", agent_process.pid)
      Process.wait(agent_process.pid)
      engine
    end

    it("does not take it back") { expect(heard).not_to include("reattached") }
    it("runs the agent again, as a stranded stage") { expect(started).to eq(2) }
  end
end
