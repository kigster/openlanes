# frozen_string_literal: true

# M2 in the prompt: every agent is told how to keep its journal, and is
# handed what it already holds, so reading it does not depend on the agent.
RSpec.describe OpenLanes::Execution::Prompt, :tree do
  subject(:text) { described_class.new(agent:, subject: plan, root: File.dirname(plans_root), profile:).to_s }

  let(:agent) { OpenLanes::Agents.find("luke-backend") }
  let(:profile) { OpenLanes::Agents::Profile.resolve(agent) }
  let(:plan) do
    plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end
  let(:state) { OpenLanes::Plans::PlanState.for(plan.feature.path) }
  let(:entry) { OpenLanes::Plans::Journal::Entry }

  it "tells the agent to print each entry as it happens, in the shape the parser reads" do
    expect(text).to include("the moment it happens", OpenLanes::Plans::Journal.line("decision", "Store money as integer cents, as the API already does"))
  end

  it "names every kind" do
    expect(text).to include(*OpenLanes::Plans::Journal::KINDS.map { "  #{it}" })
  end

  it "says the journal is empty on a first round" do
    expect(text).to include("Your journal on this plan is empty")
  end

  context "when earlier rounds left a journal" do
    before do
      state.journal!(agent: "luke-backend",
        entries: [entry.new(kind: "decision", text: "Integer cents"),
                  entry.new(kind: "done", text: "U1")],
        state: :building)
      state.journal!(agent: "luke-backend", entries: [entry.new(kind: "override", text: "BigDecimal", overrides: 1)])
      state.answer!(agent: "luke-backend", ref: "B1", question: "B1 Which DB?", answer: "Postgres")
      state.journal!(agent: "rey-frontend", entries: [entry.new(kind: "note", text: "not luke's")])
    end

    it "lists every round's entries, numbered across rounds" do
      expect(text).to include("  Journal round 1 (building):\n    1. [decision] Integer cents  (overridden by 3)\n    2. [done] U1",
        "  Journal round 2:\n    3. [override of 1] BigDecimal\n    4. [question B1] B1 Which DB? -> answered: Postgres")
    end

    it "leaves out another agent's journal" do
      expect(text).not_to include("not luke's")
    end
  end

  context "when the journal is longer than the prompt carries" do
    before do
      entries = (1..(described_class::JOURNAL_LIMIT + 2)).map { entry.new(kind: "note", text: "note #{it}") }
      state.journal!(agent: "luke-backend", entries:)
    end

    it "keeps the newest, and says how to read the rest" do
      aggregate_failures do
        expect(text).not_to include("[note] note 2\n")
        expect(text).to include("[note] note 3\n", "[note] note #{described_class::JOURNAL_LIMIT + 2}")
        expect(text).to include("2 earlier entries are not shown", "jq '.memory.\"luke-backend\"'")
      end
    end
  end

  it "says so when state.json cannot be read" do
    File.write(state.path, "{")
    expect(text).to include("Your journal could not be read")
  end
end
