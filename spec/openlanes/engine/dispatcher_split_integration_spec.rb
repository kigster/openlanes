# frozen_string_literal: true

require "yaml"

# Plan 045.02: the dispatcher was cut into steps and collaborators with no
# behaviour change, and this is the proof. A real Runner drives the real
# Dispatcher under --isolation shared, with only the agent CLI scripted: one
# plan is planned and moves 📋 → ⭐ → 🟡, the other's planner asks a question
# and the plan blocks. What the run left behind, folder names after each
# tick, the signatures in each state.json, blocked.md and the board, is
# compared with the same run recorded on main before the split.
#
# To record the fixture again, run this file on the commit to compare
# against with OPENLANES_CAPTURE_FIXTURE=1; it then writes the fixture
# instead of reading it.
RSpec.describe "the dispatcher after its split, against the run recorded on main", :tree do
  let(:fixture) { File.expand_path("../../fixtures/dispatcher_split/run.yml", __dir__) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agents) { OpenLanes::Agents::Registry.new }
  let(:state) { OpenLanes::Engine::StateFile.new(path: OpenLanes::Engine::StateFile.for(tree)) }
  let(:stamp) { "2026-09-04 11:29:20 AM PDT" }
  let(:spec_text) { "---\nfrontend: false\n---\n#{spec_body}\n## Research\n\nFound.\n" }
  let(:question) { "## B1 Which feed format the import reads\n\nThe importer needs one format.\n\na) CSV (Recommended)\nb) JSON\n" }
  let(:ticks) { [] }
  # The agent CLI, scripted: planner plans the first plan and blocks the
  # second; backend-coder starts and signs no outcome.
  let(:executor) do
    lambda { |agent, subject, round: 1, **|
      file = File.join(subject.feature.path, agent.ledger.first)
      OpenLanes::Plans::Ledger.append(file, "> [#{stamp}] [ agent: #{agent.name}   status: Started, round #{round} ]")
      outcome = outcome_of(agent, subject)
      OpenLanes::Plans::Ledger.append(file, "> [#{stamp}] [ agent: #{agent.name}   status: #{outcome}, round #{round} ]") if outcome
      OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 10, down: 2, subagents: 0, delegated: 0, seconds: 1.0)
    }
  end
  let(:runner) do
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :shared,
      jobs: 1,
      state:,
      sleeper: ->(_) {},
      extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false),
      rounds: 1)
  end

  before do
    plans do |t|
      t.plan "001.00", :ready_for_planning, "tax-rule-dsl", files: { "spec.md" => spec_text, "plan.md" => "" }
      t.plan "002.00", :ready_for_planning, "import-feed", files: { "spec.md" => spec_text, "plan.md" => "" }
    end
  end

  def outcome_of(agent, subject)
    return nil unless agent.name == "planner"
    return File.write(File.join(subject.feature.path, "blocked.md"), question) && "Blocked" if subject.feature.ordinal.to_s == "002.00"

    spec = File.join(subject.feature.path, "spec.md")
    File.write(spec, File.read(spec).sub("---\n", "---\ndepends_on: [none]\n"))
    File.write(File.join(subject.feature.path, "plan.md"), "# Plan\n\n## Backend\n\n### U1 Parse\n")
    "Completed"
  end

  def names = tree.reload.subjects.map { File.basename(it.feature.path) }.sort

  def path_of(ordinal) = tree.reload.find(OpenLanes::Plans::Ordinal.parse(ordinal)).feature.path

  def signatures(ordinal) = OpenLanes::Plans::PlanState.for(path_of(ordinal)).signatures.map { it.values_at("agent", "status", "round", "note") }

  # The board as text, in an order that does not depend on which thread settled first.
  def board_text(board)
    ["status: #{board.status}", "plans: #{board.plans.sort.join(" ")}", "running: #{board.running}", "up: #{board.up}", "down: #{board.down}",
     *board.rows.map { "#{it.ordinal} #{it.agent} #{it.state}" }.sort].join("\n")
  end

  # Folder names before each tick, consecutive repeats collapsed: how many
  # ticks a thread takes to finish is timing, the order the folders move in
  # is not. The board is read once the run is over, when every row has settled.
  def recorded
    held = nil
    attempts = runner.call do |dispatcher|
      held = dispatcher
      dispatcher.before_tick { ticks << names }
    end
    { "ticks" => [*ticks, names].chunk_while { |a, b| a == b }.map(&:first), **left_behind(attempts, held.board) }
  end

  def left_behind(attempts, board)
    { "signatures" => { "001.00" => signatures("001.00"), "002.00" => signatures("002.00") },
      "blocked"    => File.read(File.join(path_of("002.00"), "blocked.md")),
      "attempts"   => attempts.map { [it.ordinal, it.agent, it.from.to_s, it.to.to_s, it.ok, it.status] }.sort,
      "board"      => board_text(board) }
  end

  it "leaves the folders, the signatures, blocked.md and the board exactly as main did" do
    run = recorded
    if ENV["OPENLANES_CAPTURE_FIXTURE"]
      FileUtils.mkdir_p(File.dirname(fixture))
      File.write(fixture, YAML.dump(run))
    end
    expect(run).to eq(YAML.safe_load_file(fixture, permitted_classes: [Symbol]))
  end
end
