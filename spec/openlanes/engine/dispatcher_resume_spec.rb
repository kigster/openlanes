# frozen_string_literal: true

# M1 from the loop's side: every round's session goes into its stage in
# state.json, with the checkout it ran in, and the agent's next round on the
# same state is handed that session to resume. The executor here is a
# lambda that names a session per round and fails, so the agent is given a
# second round without the plan moving.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:root) { File.dirname(plans_root) }
  let(:adapter) { "claude" }
  let(:agents_dir) { Dir.mktmpdir }
  let(:agents) do
    File.write(File.join(agents_dir, "leah.md"),
      "---\nname: leah-researcher\nhandles: [new]\nadvances_to: researched\nrounds: 2\n" \
      "adapter: #{adapter}\nledger: [spec.md]\n---\nbody")
    OpenLanes::Agents::Registry.new(dir: agents_dir)
  end
  let(:folder) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).feature.path }
  let(:stages) { OpenLanes::Plans::PlanState.for(folder).stages }
  let(:calls) { [] }
  let(:heard) { [] }
  let(:executor) do
    lambda { |_agent, _subject, round: 1, handle: nil, resume: nil, root: nil, **|
      calls << { round:, resume:, root: }
      handle.session = "sess-#{round}"
      OpenLanes::Execution::Executor::Result.new(ok: false,
        note: "exited 1",
        up: 0,
        down: 0,
        subagents: 0,
        delegated: 0,
        seconds: 0.0)
    }
  end
  let!(:tap) { OpenLanes::UI.tap_log(->(message, _) { heard << message }) }

  before do
    plans { |t| t.plan "001.00", :new, "carry-on", files: { "spec.md" => spec_body } }
    OpenLanes::Engine::Runner.new(tree:, executor:, agents:, isolation: :shared, jobs: 1, sleeper: ->(_) {}).call
  end

  after do
    OpenLanes::UI.untap_log(tap)
    FileUtils.rm_rf(agents_dir)
  end

  it "keeps every round's session and checkout in its stage" do
    expect(stages.map { it.values_at("round", "session", "cwd") }).to eq([[1, "sess-1", root], [2, "sess-2", root]])
  end

  it "starts the first round fresh and resumes it in the second" do
    expect(calls.map { it[:resume] }).to eq([nil, "sess-1"])
  end

  it "says which it chose, and why" do
    expect(heard).to include("fresh session: no session recorded for leah-researcher",
      "resuming session sess-1: round 1 left it in new")
  end

  context "when the agent runs on a CLI that cannot resume" do
    let(:adapter) { "codex" }

    it "starts every round fresh, and says why" do
      aggregate_failures do
        expect(calls.map { it[:resume] }).to eq([nil, nil])
        expect(heard).to include("fresh session: codex cannot resume one")
      end
    end
  end
end
