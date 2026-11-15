# frozen_string_literal: true

# B4: a restarted engine reads the rounds an agent already spent from the
# plan's state.json, so it carries on at the next round number instead of
# telling the agent round 1 again. The first engine is capped at one round
# with `--rounds`, then stopped; a second engine, a new process as far as the
# dispatcher can tell, picks the same plan up.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agents_dir) { Dir.mktmpdir }
  let(:agents) do
    File.write(File.join(agents_dir, "researcher.md"),
      "---\nname: researcher\nhandles: [new]\nadvances_to: researched\nrounds: 3\n" \
      "adapter: claude\nledger: [spec.md]\n---\nbody")
    OpenLanes::Agents::Registry.new(dir: agents_dir)
  end
  let(:folder) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).feature.path }
  let(:stages) { OpenLanes::Plans::PlanState.for(folder).stages }
  let(:told) { [] }
  let(:note) { "exited 1" }
  let(:spent) { 1 }
  let(:extensions) { OpenLanes::Engine::Extensions.new(stay: false, auto: false) }
  let(:executor) do
    lambda { |_agent, _subject, round: 1, **|
      told << round
      OpenLanes::Execution::Executor::Result.new(ok: false,
        note:,
        up: 0,
        down: spent,
        subagents: 0,
        delegated: 0,
        seconds: 0.0)
    }
  end

  def engine(rounds: nil, &)
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :shared,
      jobs: 1,
      rounds:,
      sleeper: ->(_) {},
      extensions:).call(&)
  end

  before { plans { |t| t.plan "001.00", :new, "carry-on", files: { "spec.md" => spec_body } } }

  after { FileUtils.rm_rf(agents_dir) }

  it "tells the agent round 1, and after a restart rounds 2 and 3" do
    engine(rounds: 1)
    first = told.dup
    engine

    expect([first, told.drop(first.size)]).to eq([[1], [2, 3]])
  end

  it "spends no more rounds than the agent has across the restart" do
    engine(rounds: 1)
    engine

    expect(stages.map { it["round"] }).to eq([1, 2, 3])
  end

  it "hands out nothing to an agent that spent every round before the restart" do
    engine
    first = told.size
    engine

    expect([first, told.size]).to eq([3, 3])
  end

  context "when the CLI fails before spending anything" do
    let(:note) { "exited 1 before the first token" }
    let(:spent) { 0 }
    let(:heard) { [] }
    let(:clock) { OpenLanes::Clock::Fake.new(now: Time.now) }
    let!(:tap) { OpenLanes::UI.tap_log(->(message, _) { heard << message }) }
    let(:extensions) { OpenLanes::Engine::Extensions.new(stay: false, auto: false, now: -> { clock.now }) }

    after { OpenLanes::UI.untap_log(tap) }

    # Three runs, each past the backoff the failed start before it set.
    before do
      OpenLanes::Container.stub("clock", clock)
      [0, 31, 61].each do |wait|
        clock.advance(wait)
        engine
      end
    end

    it "hands the same round out again, and stops after three in a row" do
      expect(told).to eq([1, 1, 1])
    end

    it "keeps the agent parked across a restart, names it in the idle line, and asks a person" do
      clock.advance(3600)
      said = nil
      engine { |d| said = -> { d.send(:idle_reason, tree.reload.subjects) } }
      requests = OpenLanes::Plans::PlanState.for(folder).extensions
      aggregate_failures do
        expect(told).to eq([1, 1, 1])
        expect(said.call).to include("failed starts: 001.00 researcher (3 in a row; grant it a round to retry)")
        expect(requests.map { [it["agent"], it["limit"], it["round"]] }).to eq([["researcher", "rounds", 1]])
      end
    end

    it "asks once per run of failures, even when the request is closed unanswered" do
      engine
      OpenLanes::Plans::PlanState.for(folder).settle_extension!(1, closed: true, at: clock.now)
      clock.advance(60)
      engine
      expect(OpenLanes::Plans::PlanState.for(folder).extensions.size).to eq(1)
    end

    it "starts the agent again at the same round once a person grants it one" do
      engine
      clock.advance(1)
      extensions.answer!(folder, 1, "a", by: "dana")
      clock.advance(1)
      engine
      expect(told).to eq([1, 1, 1, 1])
    end

    it "records each one as a failed start, which spends no round" do
      rounds = OpenLanes::Plans::Rounds.from(OpenLanes::Plans::PlanState.for(folder))

      aggregate_failures do
        expect(stages.map { it["status"] }).to eq(["Failed start"] * 3)
        expect(rounds.left("researcher", :new, moves: 0, budget: 3)).to eq(3)
      end
    end

    it "says so in the log" do
      expect(heard.grep(/failed start: exited 1/).size).to eq(3)
    end
  end

  context "when a start fails and the engine is started again at once" do
    let(:note) { "exited 1 before the first token" }
    let(:spent) { 0 }
    let(:clock) { OpenLanes::Clock::Fake.new(now: Time.now) }

    before { OpenLanes::Container.stub("clock", clock) }

    it "backs off: a run inside the wait starts nothing, one after it tries again" do
      engine
      engine
      waited = told.size
      clock.advance(31)
      engine
      expect([waited, told.size]).to eq([1, 2])
    end

    it "names the agent that is backing off in the idle line" do
      engine
      said = nil
      engine { |d| said = -> { d.send(:idle_reason, tree.reload.subjects) } }
      expect(said.call).to include("failed starts: 001.00 researcher (retrying after a backoff)")
    end
  end

  context "when the CLI fails to authenticate" do
    let(:note) { "OAuth session expired" }
    let(:spent) { 0 }

    before { engine }

    it "starts no further agent on that CLI, and spends no round" do
      expect([told, stages.map { it["status"] }]).to eq([[1], ["Failed start"]])
    end
  end

  # The probe (`claude auth status`) says signed in, the run says it is not:
  # the CLI is released, the agent fails to log in, the CLI is held again.
  # Left to the pause alone that went round every ten minutes for good.
  context "when the CLI fails to authenticate although its probe passes" do
    let(:note) { "OAuth session expired" }
    let(:spent) { 0 }
    let(:clock) { OpenLanes::Clock::Fake.new(now: Time.now) }
    let(:extensions) { OpenLanes::Engine::Extensions.new(stay: false, auto: false, now: -> { clock.now }) }
    let(:cli_pause) { OpenLanes::Engine::CliPause.new(prober: ->(_) { true }, clock: -> { clock.now }) }
    let(:requests) { OpenLanes::Plans::PlanState.for(folder).extensions.map { it.values_at("agent", "cause") } }

    # Each run is one cycle: the pause released by a passing probe, and the
    # start failing again.
    def cycles(count)
      count.times do
        clock.advance(OpenLanes::Engine::CliPause::CEILING + 1)
        OpenLanes::Engine::Runner.new(tree:, executor:, agents:, isolation: :shared, jobs: 1, sleeper: ->(_) {}, extensions:, cli_pause:).call
      end
    end

    before { OpenLanes::Container.stub("clock", clock) }

    it "leaves the first failures to the pause, asking nobody" do
      cycles(2)

      expect([told, requests]).to eq([[1, 1], []])
    end

    it "stops trying after three, and asks a person" do
      cycles(5)

      expect([told, requests]).to eq([[1, 1, 1], [%w[researcher failed_starts]]])
    end

    it "tries again once a person grants it a round" do
      cycles(4)
      extensions.answer!(folder, 1, "a", by: "dana")
      cycles(1)

      expect(told).to eq([1, 1, 1, 1])
    end
  end
end
