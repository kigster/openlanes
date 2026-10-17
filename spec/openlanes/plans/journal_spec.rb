# frozen_string_literal: true

require "json_schemer"

# M2: an agent prints its journal, one line of JSON per entry, and the
# harness alone writes it into state.json under memory.<agent>.rounds.<n>.
RSpec.describe OpenLanes::Plans::Journal do
  def line(**entry) = JSON.generate(entry)

  describe ".scan" do
    it "reads entries on lines of their own, in the order printed" do
      text = "Starting.\n#{line(kind: "todo", text: "migrate")}\n#{line(kind: "decision", text: "use Redis")}\n"

      expect(described_class.scan(text).map(&:kind)).to eq(%w[todo decision])
    end

    it "keeps the number an override overturns" do
      expect(described_class.scan(line(kind: "override", text: "Postgres", overrides: 3)).first.overrides).to eq(3)
    end

    it "refuses an override that names no entry" do
      expect(described_class.scan(line(kind: "override", text: "Postgres"))).to eq([])
    end

    it "drops overrides from any other kind" do
      expect(described_class.scan(line(kind: "note", text: "x", overrides: 2)).first.overrides).to be_nil
    end

    it "ignores JSON that is not an entry" do
      text = [line(kind: "rumour", text: "x"), line(kind: "note", text: ""), line(kind: "note", text: "x", extra: 1),
              '{"kind": "note", broken', "[1, 2]", "see #{line(kind: "note", text: "inline")} above"].join("\n")

      expect(described_class.scan(text)).to eq([])
    end

    it "reads an entry wrapped in backticks" do
      expect(described_class.scan("`#{line(kind: "done", text: "U1")}`").map(&:text)).to eq(["U1"])
    end
  end

  describe ".render" do
    it "numbers each entry and names what an override overturns" do
      entries = [{ "number" => 1, "kind" => "decision", "text" => "Redis" },
                 { "number" => 2, "kind" => "override", "text" => "Postgres", "overrides" => 1 }]

      expect(described_class.render(entries)).to eq("  #1 decision: Redis\n  #2 override (overrides #1): Postgres")
    end
  end

  describe OpenLanes::Plans::PlanState, :tree do
    let(:folder) do
      path = nil
      plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => spec_body, "plan.md" => "## U1" } }
      path
    end
    let(:state) { described_class.for(folder) }
    let(:schema) { JSONSchemer.schema(Pathname.new(described_class::SCHEMA_PATH)) }

    def entries(*specs) = specs.map { OpenLanes::Plans::Journal::Entry.new(**it) }

    before do
      state.journal!(agent: "luke-backend", round: 1, entries: entries({ kind: "todo", text: "U1" }, { kind: "decision", text: "Redis" }))
      state.journal!(agent: "luke-backend", round: 1, entries: entries({ kind: "done", text: "U1" }))
      state.journal!(agent: "luke-backend", round: 2, entries: entries({ kind: "override", text: "Postgres", overrides: 2 }))
      state.journal!(agent: "rey-frontend", round: 1, entries: entries({ kind: "note", text: "dark mode" }))
    end

    it "keeps a round's entries in the order they were printed" do
      expect(state.journal("luke-backend", 1).map { it["kind"] }).to eq(%w[todo decision done])
    end

    it "numbers entries across the agent's rounds, so an override can reach back" do
      expect(state.journal("luke-backend", 2)).to eq([{ "number" => 4, "kind" => "override", "text" => "Postgres", "overrides" => 2 }])
    end

    it "numbers each agent's journal on its own" do
      expect(state.journal("rey-frontend", 1).first["number"]).to eq(1)
    end

    it "writes a document the schema accepts" do
      expect(schema.validate(JSON.parse(File.read(state.path))).map { |e| e["error"] }).to eq([])
    end

    it "has the schema refuse an override that names nothing" do
      data = JSON.parse(File.read(state.path))
      data["memory"]["luke-backend"]["rounds"]["2"].first.delete("overrides")

      expect(schema.valid?(data)).to be(false)
    end

    it "keeps an override of no earlier entry as a note, under its own number" do
      written = state.journal!(agent: "rey-frontend",
        round: 2,
        entries: entries({ kind: "override", text: "x", overrides: 99 }, { kind: "override", text: "y", overrides: 3 }))

      expect(written).to eq([{ "number" => 2, "kind" => "note", "text" => "x" }, { "number" => 3, "kind" => "note", "text" => "y" }])
    end

    it "says what number the agent's next entry takes" do
      expect([state.next_journal_number("luke-backend"), state.next_journal_number("leia-planner")]).to eq([5, 1])
    end

    it "writes nothing for nothing" do
      expect(state.journal!(agent: "luke-backend", round: 3, entries: [])).to eq([])
    end

    it "refuses an agent name that is not one token" do
      expect { state.journal!(agent: "two words", round: 1, entries: entries({ kind: "note", text: "x" })) }
        .to raise_error(OpenLanes::Error, /agent name/)
    end

    it "answers an empty list for a round with no journal" do
      expect(state.journal("luke-backend", 9)).to eq([])
    end
  end
end
