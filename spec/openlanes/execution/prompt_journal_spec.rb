# frozen_string_literal: true

# M2 in the prompt: every agent is told how to keep its journal, and is
# handed what it already holds, so reading it does not depend on the agent.
RSpec.describe OpenLanes::Execution::Prompt, :tree do
  subject(:text) { described_class.new(agent:, subject: plan, root: File.dirname(plans_root), profile:).to_s }

  let(:agent) { OpenLanes::Agents.find("backend-coder") }
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

  # PlanState reads a missing file as an empty document, so a brand-new
  # plan's prompt builds rather than raising Errno::ENOENT.
  it "builds for a plan that has no state.json yet" do
    expect([File.exist?(state.path), text]).to match([false, include("Your journal on this plan is empty")])
  end

  context "when earlier rounds left a journal" do
    before do
      state.journal!(agent: "backend-coder",
        entries: [entry.new(kind: "decision", text: "Integer cents"),
                  entry.new(kind: "done", text: "U1")],
        state: :building)
      state.journal!(agent: "backend-coder", entries: [entry.new(kind: "override", text: "BigDecimal", overrides: 1)])
      state.answer!(agent: "backend-coder", ref: "B1", question: "B1 Which DB?", answer: "Postgres")
      state.journal!(agent: "frontend-coder", entries: [entry.new(kind: "note", text: "not backend-coder's")])
    end

    it "lists every round's entries, numbered across rounds" do
      expect(text).to include("  Journal round 1 (building):\n    1. [decision] Integer cents  (overridden by 3)\n    2. [done] U1",
        "  Journal round 2:\n    3. [override of 1] BigDecimal\n    4. [question B1] B1 Which DB? -> answered: Postgres")
    end

    it "leaves out another agent's journal" do
      expect(text).not_to include("not backend-coder's")
    end
  end

  # Plan 062.00: a session that is resumed already holds the instructions
  # and the entries before it, so they are not paid for a second time.
  context "when the round resumes a session that holds the journal" do
    subject(:text) do
      described_class.new(agent:, subject: plan, root: File.dirname(plans_root), profile:, resume: "sess-1").to_s
    end

    before do
      state.journal!(agent: "backend-coder",
        entries: [entry.new(kind: "decision", text: "Integer cents"), entry.new(kind: "done", text: "U1")],
        state: :building)
      state.hold!(agent: "backend-coder", session: "sess-1")
    end

    it "says so in one line, in place of the instructions" do
      aggregate_failures do
        expect(text).to include("## Your journal - carry on",
          "already holds how to keep your journal and its entries 1 to 2",
          "the next is number 3")
        expect(text).not_to include("the moment it happens", "Read your journal so far")
      end
    end

    it "sends none of the entries the session holds" do
      expect([text.include?("Nothing has been added to it since."), text.include?("Integer cents")]).to eq([true, false])
    end

    context "with entries written since" do
      before do
        state.journal!(agent: "backend-coder", entries: [entry.new(kind: "override", text: "BigDecimal", overrides: 1)], state: :building)
      end

      it "sends only those, numbered as the journal numbers them" do
        aggregate_failures do
          expect(text).to include("Added since, all of it:", "  Journal round 2 (building):\n    3. [override of 1] BigDecimal", "the next is number 4")
          expect(text).not_to include("[decision] Integer cents")
        end
      end
    end

    context "with more written since than a prompt carries" do
      before do
        entries = (1..(described_class::JOURNAL_LIMIT + 1)).map { entry.new(kind: "note", text: "later #{it}") }
        state.journal!(agent: "backend-coder", entries:)
      end

      it "keeps the newest" do
        aggregate_failures do
          expect(text).to include("the newest #{described_class::JOURNAL_LIMIT} of it", "[note] later 2\n")
          expect(text).not_to include("[note] later 1\n")
        end
      end
    end

    context "when the session being resumed is another one" do
      before { state.hold!(agent: "backend-coder", session: "sess-0") }

      it "sends the whole journal and the instructions" do
        expect(text).to include("the moment it happens", "1. [decision] Integer cents", "2. [done] U1")
      end
    end
  end

  context "when a resumed session held an empty journal" do
    subject(:text) do
      described_class.new(agent:, subject: plan, root: File.dirname(plans_root), profile:, resume: "sess-1").to_s
    end

    before { state.hold!(agent: "backend-coder", session: "sess-1") }

    it "says the journal is empty so far" do
      expect(text).to include("how to keep your journal, empty so far", "the next is number 1")
    end
  end

  context "when the journal is longer than the prompt carries" do
    before do
      entries = (1..(described_class::JOURNAL_LIMIT + 2)).map { entry.new(kind: "note", text: "note #{it}") }
      state.journal!(agent: "backend-coder", entries:)
    end

    it "keeps the newest, and says how to read the rest" do
      aggregate_failures do
        expect(text).not_to include("[note] note 2\n")
        expect(text).to include("[note] note 3\n", "[note] note #{described_class::JOURNAL_LIMIT + 2}")
        expect(text).to include("2 earlier entries are not shown", "jq '.memory.\"backend-coder\"'")
      end
    end
  end

  it "says so when state.json cannot be read" do
    File.write(state.path, "{")
    expect(text).to include("Your journal could not be read")
  end
end
