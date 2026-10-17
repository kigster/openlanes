# frozen_string_literal: true

require "json_schemer"

# M2 on disk: the dispatcher appends what an agent printed under
# memory.<agent>.rounds.<n>, numbering entries across rounds.
RSpec.describe OpenLanes::Plans::PlanState, :tree do
  subject(:state) { described_class.for(folder) }

  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => spec_body, "plan.md" => "## U1" } }
    path
  end
  let(:schema) { JSONSchemer.schema(Pathname.new(described_class::SCHEMA_PATH)) }
  let(:written) { JSON.parse(File.read(state.path)) }
  let(:entry) { OpenLanes::Plans::Journal::Entry }

  describe "#journal!" do
    before do
      number, = state.journal!(agent: "luke-backend", entries: [entry.new(kind: "todo", text: "U1")], round: 1, state: :building)
      state.journal!(agent: "luke-backend", entries: [entry.new(kind: "done", text: "U1")], number:)
      state.journal!(agent: "luke-backend", entries: [entry.new(kind: "override", text: "U1 again", overrides: 1)], round: 1)
    end

    it "keeps each dispatch in a journal round of its own, numbered 1 up" do
      expect(written.dig("memory", "luke-backend", "rounds").transform_values { it["entries"].map { |e| e["kind"] } })
        .to eq("1" => %w[todo done], "2" => ["override"])
    end

    it "numbers entries across rounds" do
      expect(state.journal("luke-backend").map { [it.number, it.first, it.entries.size] }).to eq([[1, 1, 2], [2, 3, 1]])
    end

    it "keeps the dispatcher's round and state beside the entries" do
      expect(written.dig("memory", "luke-backend", "rounds", "1").slice("round", "state")).to eq("round" => 1, "state" => "building")
    end

    it "writes a document the schema accepts" do
      expect(schema.validate(written).map { it["error"] }).to eq([])
    end

    it "refuses an override of an entry not before it, and writes the rest" do
      _, refused = state.journal!(agent: "luke-backend",
        entries: [entry.new(kind: "override", text: "ahead", overrides: 9), entry.new(kind: "note", text: "kept")])
      expect([refused.map(&:reason), state.journal("luke-backend").last.entries.map(&:text)])
        .to eq([["entry 4 overrides 9, which is not before it"], ["kept"]])
    end

    it "reads nothing for an agent that never journaled" do
      expect(state.journal("rey-frontend")).to eq([])
    end
  end

  describe "#answer!" do
    before { state.journal!(agent: "yoda-writer", entries: [entry.new(kind: "question", text: "Which DB?")]) }

    it "adds the question and its answer to the asker's latest round, once" do
      2.times { state.answer!(agent: "yoda-writer", ref: "B1", question: "B1 Which DB?", answer: "Postgres") }
      expect(state.journal("yoda-writer").map { it.entries.map(&:to_json_h) }).to eq([[
                                                                                       { "kind" => "question", "text" => "Which DB?" },
                                                                                       { "kind" => "question", "text" => "B1 Which DB?", "ref" => "B1", "answer" => "Postgres" }
                                                                                     ]])
    end

    it "is accepted by the schema" do
      state.answer!(agent: "yoda-writer", ref: "B1", question: "B1 Which DB?", answer: "Postgres")
      expect(schema.validate(written).map { it["error"] }).to eq([])
    end
  end

  describe "#blocked_by" do
    it "names the agent whose round last settled Blocked" do
      state.stage!(agent: "luke-backend", round: 1, status: "Blocked", started_at: "2026-10-16T10:00:00Z")
      state.stage!(agent: "rey-frontend", round: 1, status: "Completed", started_at: "2026-10-16T11:00:00Z")
      expect(state.blocked_by).to eq("luke-backend")
    end

    it "falls back to a Blocked signature" do
      state.sign!(agent: "yoda-writer", round: 1, status: "Blocked")
      expect(state.blocked_by).to eq("yoda-writer")
    end

    it "is nil when nothing ever blocked" do
      expect(state.blocked_by).to be_nil
    end
  end

  it "rejects an entry kind the journal does not have" do
    data = JSON.parse(File.read(state.tap { it.journal!(agent: "a", entries: [entry.new(kind: "note", text: "x")]) }.path))
    data["memory"]["a"]["rounds"]["1"]["entries"][0]["kind"] = "wish"
    expect(schema.validate(data).to_a).not_to be_empty
  end
end
