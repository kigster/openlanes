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

  def engine(rounds: nil)
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :shared,
      jobs: 1,
      rounds:,
      sleeper: ->(_) {},
      extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false)).call
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
    let!(:tap) { OpenLanes::UI.tap_log(->(message, _) { heard << message }) }

    after { OpenLanes::UI.untap_log(tap) }

    before { engine }

    it "hands the same round out again, and stops after three in a row" do
      expect(told).to eq([1, 1, 1])
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

  context "when the CLI fails to authenticate" do
    let(:note) { "OAuth session expired" }
    let(:spent) { 0 }

    before { engine }

    it "starts no further agent on that CLI, and spends no round" do
      expect([told, stages.map { it["status"] }]).to eq([[1], ["Failed start"]])
    end
  end
end
