# frozen_string_literal: true

# Plan 024, B1: M1 with nothing stubbed between the run loop and the child
# process. The unit specs each stub one side, the dispatcher's executor or the
# executor's process, so neither proves that round 2's real `claude` argv
# carries round 1's session. Here a real Runner drives the real Executor,
# which spawns a fake `claude` from a temp bin: the fake logs its argv, names
# a session `sess-<n>` for its n-th start and fails, so the plan stays put and
# the agent gets its second round.
RSpec.describe "resuming an agent's session across rounds", :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:root) { File.dirname(plans_root) }
  let(:adapter) { "claude" }
  let(:agents_dir) { Dir.mktmpdir }
  let(:agents) do
    File.write(File.join(agents_dir, "researcher.md"),
      "---\nname: researcher\nhandles: [new]\nadvances_to: researched\nrounds: 2\n" \
      "adapter: #{adapter}\nledger: [spec.md]\n---\nbody")
    OpenLanes::Agents::Registry.new(dir: agents_dir)
  end
  let(:bin) { Dir.mktmpdir("openlanes-fake-cli") }
  let(:argv_log) { File.join(bin, "argv.log") }
  # Only the temp bin and the system's own: no real `claude` or `codex` can be
  # found, so a fake that failed to install fails the spec instead of
  # starting a paid session.
  let(:path) { "#{bin}:/usr/bin:/bin" }
  let(:lost) { false }
  let(:seed) { nil }
  let(:folder) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).feature.path }
  let(:stages) { OpenLanes::Plans::PlanState.for(folder).stages.select { it["agent"] == "researcher" } }
  let(:heard) { [] }
  let!(:tap) { OpenLanes::UI.tap_log(->(message, _) { heard << message }) }
  # Each invocation's argv, one argument per element.
  let(:invocations) { File.readlines(argv_log, chomp: true).map { it.split("\x1f") } }
  let(:resumed) { invocations.map { |argv| argv[argv.index("--resume") + 1] if argv.include?("--resume") } }

  # The real agent supervisor (S6), through the executor's own seam, with
  # PATH pointed at the fakes: agents start in Bundler's unbundled
  # environment, whose PATH was fixed when Bundler loaded, so changing ENV
  # here would not reach them.
  let(:executor) do
    starter = OpenLanes::Execution::AgentProcess.spawner(dir: File.join(bin, "traces"), root:)
    spawn = lambda { |argv, chdir:, env:, label:|
      starter.call(argv, chdir:, env: env.merge("PATH" => path), label:)
    }
    OpenLanes::Execution::Executor.new(root:, spawn:, trace_dir: File.join(bin, "traces"))
  end

  # A `claude` that names a session and fails having spent a little, as a
  # real one does when it runs and gives up. Spending nothing would read as
  # a session that failed at start-up and be retried fresh. With +lost+, a
  # `--resume` is answered as `claude` answers an id it has no session for.
  def fake_claude(lost:)
    <<~SH
      #!/bin/sh
      n=$(( $(cat '#{argv_log}' 2>/dev/null | wc -l) + 1 ))
      resume=""
      prev=""
      for arg in "$@"; do
        [ "$prev" = "--resume" ] && resume="$arg"
        prev="$arg"
        printf '%s\\037' "$arg" | tr '\\n' ' '
      done >> '#{argv_log}'
      echo >> '#{argv_log}'
      if [ -n "$resume" ] && [ "#{lost}" = "true" ]; then
        echo "No conversation found with session ID: $resume" >&2
        exit 1
      fi
      echo '{"type":"system","subtype":"init","session_id":"sess-'$n'"}'
      echo '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"fake claude gave up","session_id":"sess-'$n'","usage":{"input_tokens":10,"output_tokens":5}}'
      exit 1
    SH
  end

  # A `codex` that logs its argv and fails; it has no sessions to name.
  def fake_codex
    <<~SH
      #!/bin/sh
      for arg in "$@"; do printf '%s\\037' "$arg" | tr '\\n' ' '; done >> '#{argv_log}'
      echo >> '#{argv_log}'
      echo '{"type":"error","message":"fake codex gave up"}'
      exit 1
    SH
  end

  before do
    { "claude" => fake_claude(lost:), "codex" => fake_codex }.each do |name, body|
      File.write(File.join(bin, name), body)
      File.chmod(0o755, File.join(bin, name))
    end
    plans { |t| t.plan "001.00", :new, "carry-on", files: { "spec.md" => spec_body } }
    seed
    # No round granted on its own (E1): the agent's two rounds are the ones counted here.
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :shared,
      jobs: 1,
      sleeper: ->(_) {},
      extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false)).call
  end

  after do
    OpenLanes::UI.untap_log(tap)
    FileUtils.rm_rf([agents_dir, bin])
  end

  it "keeps every round's session and checkout in its stage" do
    expect(stages.map { it.values_at("round", "session", "cwd") }).to eq([[1, "sess-1", root], [2, "sess-2", root]])
  end

  it "starts round 1 fresh and resumes its session in round 2" do
    expect(resumed).to eq([nil, "sess-1"])
  end

  it "says which it chose, and why" do
    expect(heard).to include("fresh session: no session recorded for researcher",
      "resuming session sess-1: round 1 left it in new")
  end

  context "when the session cannot be found" do
    let(:lost) { true }

    it "starts round 2 again fresh, and says why" do
      aggregate_failures do
        expect(resumed).to eq([nil, "sess-1", nil])
        expect(heard).to include("session sess-1 not found, starting researcher fresh")
        expect(stages.map { it.values_at("round", "session") }).to eq([[1, "sess-1"], [2, "sess-3"]])
      end
    end
  end

  context "when the plan has moved since the agent's last session" do
    # An earlier run's round 1 left the plan in researched; it is back in new.
    let(:seed) do
      OpenLanes::Plans::PlanState.for(folder).stage!(agent: "researcher",
        round: 1,
        session: "sess-0",
        cwd: root,
        started_at: "2026-01-01T00:00:00Z",
        to: "researched")
    end

    it "starts fresh, and says why" do
      aggregate_failures do
        expect(resumed).to eq([nil, "sess-1"])
        expect(heard).to include("fresh session: the plan moved to researched after round 1 (sess-0)")
      end
    end
  end

  context "when the agent runs on a CLI that cannot resume" do
    let(:adapter) { "codex" }

    it "starts every round fresh, and says why" do
      aggregate_failures do
        expect(invocations.map(&:first)).to eq(%w[exec exec])
        expect(invocations.flatten).not_to include("--resume")
        expect(heard).to include("fresh session: codex cannot resume one")
      end
    end
  end
end
