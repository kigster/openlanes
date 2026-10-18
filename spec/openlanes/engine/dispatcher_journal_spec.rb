# frozen_string_literal: true

# M2 from the loop's side: what an agent prints as journal lines goes into
# its plan's state.json under its own name, in order, while it runs and
# whatever way it ends. The executor here is a lambda that reports a journal
# through its progress block and then fails, so the agent gets two rounds.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agents_dir) { Dir.mktmpdir }
  let(:agents) do
    File.write(File.join(agents_dir, "leah.md"),
      "---\nname: leah-researcher\nhandles: [new]\nadvances_to: researched\nrounds: 2\n" \
      "adapter: claude\nledger: [spec.md]\n---\nbody")
    OpenLanes::Agents::Registry.new(dir: agents_dir)
  end
  let(:folder) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).feature.path }
  let(:state) { OpenLanes::Plans::PlanState.for(folder) }
  let(:journal) { OpenLanes::Plans::Journal }
  let(:heard) { [] }
  let(:executor) do
    lambda { |_agent, _subject, round: 1, **, &progress|
      lines = journal.scan("#{journal.line("todo", "round #{round}")}\n" \
                           "#{journal.line("done", "round #{round}")}\n" \
                           '{"openlanes_memory": {"kind": "wish", "text": "x"}}')
      progress.call(OpenLanes::Execution::Transcript::Progress.new(activity: nil, up: 0, down: 0, subagents: 0, journal: lines.first(1)))
      progress.call(OpenLanes::Execution::Transcript::Progress.new(activity: nil, up: 0, down: 0, subagents: 0, journal: lines))
      OpenLanes::Execution::Executor::Result.new(ok: false, note: "killed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
    }
  end
  let!(:tap) { OpenLanes::UI.tap_log(->(message, _) { heard << message }) }

  before do
    plans { |t| t.plan "001.00", :new, "remember", files: { "spec.md" => spec_body } }
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
    FileUtils.rm_rf(agents_dir)
  end

  it "keeps every entry a failed round printed, each round in its own journal round" do
    expect(state.journal("leah-researcher").map { [it.number, it.round, it.state, it.entries.map(&:to_json_h)] }).to eq([
                                                                                                                          [1, 1, "new", [{ "kind" => "todo", "text" => "round 1" }, { "kind" => "done", "text" => "round 1" }]],
                                                                                                                          [2, 2, "new", [{ "kind" => "todo", "text" => "round 2" }, { "kind" => "done", "text" => "round 2" }]]
                                                                                                                        ])
  end

  it "says which lines it ignored, and why" do
    expect(heard.grep(/journal line ignored/).size).to eq(2)
  end

  it "writes a document the schema accepts" do
    require "json_schemer"
    schema = JSONSchemer.schema(Pathname.new(OpenLanes::Plans::PlanState::SCHEMA_PATH))
    expect(schema.validate(JSON.parse(File.read(state.path))).map { it["error"] }).to eq([])
  end
end
