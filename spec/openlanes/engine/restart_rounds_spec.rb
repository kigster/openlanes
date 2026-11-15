# frozen_string_literal: true

require "rbconfig"

# Plan 065.00, B6: rounds across a restart and an outage, with nothing in lib/
# stubbed. A real Runner drives the real Executor, which spawns a fake
# `claude` from a temp bin. In `sign` mode the fake signs the round its prompt
# names through the real `openlanes state sign` and stops short of done, so
# the agent is given its next round; in `auth` mode it fails to log in, as a
# signed-out `claude` does, having spent nothing.
RSpec.describe "rounds across an engine restart", :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:root) { File.dirname(plans_root) }
  let(:agents_dir) { Dir.mktmpdir }
  let(:agents) do
    File.write(File.join(agents_dir, "researcher.md"),
      "---\nname: researcher\nhandles: [new]\nadvances_to: researched\nrounds: 3\n" \
      "adapter: claude\nledger: [spec.md]\n---\nbody")
    OpenLanes::Agents::Registry.new(dir: agents_dir)
  end
  let(:bin) { Dir.mktmpdir("openlanes-fake-cli") }
  let(:told_log) { File.join(bin, "told.log") }
  let(:mode_file) { File.join(bin, "mode") }
  # Only the temp bin and the system's own, so no real `claude` is found.
  let(:path) { "#{bin}:/usr/bin:/bin" }
  let(:folder) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).feature.path }
  let(:stages) { OpenLanes::Plans::PlanState.for(folder).stages.select { it["agent"] == "researcher" } }
  let(:told) { File.exist?(told_log) ? File.readlines(told_log, chomp: true).map(&:to_i) : [] }
  let(:heard) { [] }
  let!(:tap) { OpenLanes::UI.tap_log(->(message, _) { heard << message }) }
  # The suite's own bundle, handed back to the agent's environment. The
  # executor starts an agent outside the harness's bundle (`Child.environment`),
  # which is right for a real `claude`, but the fake signs through this
  # checkout's `exe/openlanes`: where the gems live in `vendor/bundle`, as on
  # CI, that process found none of them, signed nothing, and the engine
  # reported `no closing ledger line` for every round.
  let(:bundle) { ENV.to_h.slice("BUNDLE_GEMFILE", "BUNDLE_PATH", "BUNDLE_BIN_PATH", "RUBYOPT", "RUBYLIB", "GEM_HOME", "GEM_PATH") }
  let(:executor) do
    starter = OpenLanes::Execution::AgentProcess.spawner(dir: File.join(bin, "traces"), root:)
    spawn = lambda { |argv, chdir:, env:, label:|
      starter.call(argv, chdir:, env: env.merge(bundle, "PATH" => path), label:)
    }
    OpenLanes::Execution::Executor.new(root:, spawn:, trace_dir: File.join(bin, "traces"))
  end
  let(:exe) { File.expand_path("../../../exe/openlanes", __dir__) }

  # Reads the round from the prompt's own ledger command, the one the agent
  # is told to sign with, so what it signs is exactly what it was told.
  def fake_claude
    <<~SH
      #!/bin/sh
      round=$(printf '%s ' "$@" | sed -n 's/.*--agent researcher --round \\([0-9]*\\).*/\\1/p' | head -n 1)
      echo "$round" >> '#{told_log}'
      if [ "$(cat '#{mode_file}')" = "auth" ]; then
        echo "OAuth session expired. Please run /login" >&2
        exit 1
      fi
      '#{RbConfig.ruby}' '#{exe}' state sign --dir '#{plans_root}' --plan 001.00 --agent researcher \
        --round "$round" --status "Almost completed" >/dev/null 2>&1
      echo '{"type":"system","subtype":"init","session_id":"sess-'$round'"}'
      echo '{"type":"result","subtype":"success","is_error":false,"result":"part done","session_id":"sess-'$round'","usage":{"input_tokens":10,"output_tokens":5}}'
      exit 0
    SH
  end

  def mode(name) = File.write(mode_file, name)

  def engine(rounds: nil, cli_pause: nil)
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :shared,
      jobs: 1,
      rounds:,
      cli_pause:,
      sleeper: ->(_) {},
      extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false)).tap(&:call)
  end

  before do
    File.write(File.join(bin, "claude"), fake_claude)
    File.chmod(0o755, File.join(bin, "claude"))
    mode("sign")
    plans { |t| t.plan "001.00", :new, "carry-on", files: { "spec.md" => spec_body } }
  end

  after do
    OpenLanes::UI.untap_log(tap)
    FileUtils.rm_rf([agents_dir, bin])
  end

  context "when the engine is stopped after round 1 and started again" do
    before do
      engine(rounds: 1)
      engine
    end

    it "tells the agent round 2 next, and it signs the round it was told" do
      signed = OpenLanes::Plans::PlanState.for(folder).read["signatures"].select { it["agent"] == "researcher" }

      # The status too: the harness signs `Interrupted` under the same round
      # for an agent that signed nothing, which the rounds alone cannot tell apart.
      expect([told, signed.map { [it["round"], it["status"]] }])
        .to eq([[1, 2, 3], [1, 2, 3].map { [it, "Almost completed"] }])
    end

    it "leaves the rounds left at the budget less those spent" do
      rounds = OpenLanes::Plans::Rounds.from(OpenLanes::Plans::PlanState.for(folder))

      expect(rounds.left("researcher", :new, moves: 0, budget: 3)).to eq(0)
    end

    it "never reports a missing closing ledger line" do
      expect([stages.map { it["note"] }, heard].flatten.compact.grep(/no closing ledger line/)).to be_empty
    end
  end

  context "when claude fails to authenticate" do
    let(:clock) { [Time.utc(2026, 11, 14, 8)] }
    let(:signed_in) { [false] }
    let(:cli_pause) { OpenLanes::Engine::CliPause.new(prober: ->(_) { signed_in.first }, clock: -> { clock.first }) }

    before do
      mode("auth")
      engine(cli_pause:)
    end

    it "starts no further claude agent, and spends no round" do
      rounds = OpenLanes::Plans::Rounds.from(OpenLanes::Plans::PlanState.for(folder))

      aggregate_failures do
        expect(told).to eq([1])
        expect(stages.map { it["status"] }).to eq(["Failed start"])
        expect(rounds.left("researcher", :new, moves: 0, budget: 3)).to eq(3)
      end
    end

    it "holds claude, saying why, for the idle line and the page" do
      expect([cli_pause.reason, cli_pause.entries.map { it.to_h[:adapter] }])
        .to eq(["claude paused: OAuth session expired; waiting for claude auth status", ["claude"]])
    end

    it "hands the same round out once a probe passes" do
      mode("sign")
      signed_in[0] = true
      clock[0] += OpenLanes::Engine::CliPause::FIRST
      engine(rounds: 1, cli_pause:)

      expect(told).to eq([1, 1])
    end
  end
end
