# frozen_string_literal: true

require "json_schemer"

RSpec.describe OpenLanes::Plans::PlanState, :tree do
  subject(:state) { described_class.for(folder) }

  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => spec_body, "plan.md" => "## U1" } }
    path
  end
  let(:schema) { JSONSchemer.schema(Pathname.new(described_class::SCHEMA_PATH)) }
  let(:written) { JSON.parse(File.read(state.path)) }

  it "reads as an empty document before anything is written" do
    expect([state.exist?, state.stages, state.signatures, state.messages]).to eq([false, [], [], []])
  end

  describe "#stage!" do
    before do
      state.stage!(agent: "luke-backend",
        round: 1,
        status: "Started",
        adapter: "claude",
        model: "opus",
        effort: "high",
        started_at: Time.now.iso8601,
        run: { "pid" => 42, "host" => "box" })
      state.stage!(agent: "luke-backend",
        round: 1,
        status: "Completed",
        up: 10,
        down: 5,
        seconds: 1.5,
        finished_at: Time.now.iso8601)
    end

    it "keeps one record per agent per round, from dispatch to settlement" do
      expect(state.stages.map { |s| s.values_at("agent", "round", "status", "model") })
        .to eq([["luke-backend", 1, "Completed", "opus"]])
    end

    it "names the plan it belongs to" do
      expect(written["plan"]).to eq("ordinal" => "001.00", "slug" => "work")
    end

    it "writes a document the schema accepts" do
      expect(schema.validate(written).map { |e| e["error"] }).to eq([])
    end
  end

  describe "#sign!" do
    let(:reading) do
      state.sign!(agent: "yoda-writer", round: 1, status: "Completed", next_agent: "palpatine-planner", note: "done")
      state.ledger
    end

    it "records a signature the ledger reads back as an entry with its handoff" do
      expect([reading.entries.first.to_h.slice(:agent, :status, :round, :note, :file),
              OpenLanes::Plans::Ledger.handoff_after(reading, reading.entries.first)&.next])
        .to eq([{ agent: "yoda-writer", status: "Completed", round: 1, note: "done", file: "state.json" },
                "palpatine-planner"])
    end

    it "refuses a status outside the ledger's vocabulary" do
      expect { state.sign!(agent: "x", round: 1, status: "Done") }.to raise_error(OpenLanes::Error, /status must be/)
    end

    it "refuses a handoff after anything but Completed" do
      expect { state.sign!(agent: "x", round: 1, status: "Blocked", next_agent: "y") }
        .to raise_error(OpenLanes::Error, /only a Completed/)
    end

    it "refuses an agent name with spaces" do
      expect { state.sign!(agent: "luke backend", round: 1, status: "Started") }.to raise_error(OpenLanes::Error)
    end

    it "is read by the ledger with the plan's documents" do
      state.sign!(agent: "luke-backend", round: 1, status: "Completed")
      expect(OpenLanes::Plans::Ledger.last_for(OpenLanes::Plans::Ledger.read(folder, %w[plan.md]), "luke-backend").file)
        .to eq("state.json")
    end
  end

  describe "#message!" do
    it "numbers messages from one, or after a number already taken" do
      state.message!(from: "a", to: "b", body: "one", after: 4)
      state.message!(from: "b", to: "a", body: "two")
      expect(state.messages.map { |m| m["number"] }).to eq([5, 6])
    end

    # A page command is applied at least once (W13): the second time it must
    # find its own message rather than say the same thing again.
    context "when one command's message is appended twice" do
      before do
        state.message!(from: "human", to: "luke-backend", body: "one", command: "01JM")
        state.message!(from: "human", to: "rey-frontend", body: "one", command: "01JM")
      end

      let!(:again) { state.message!(from: "human", to: "luke-backend", body: "one", command: "01JM") }

      it "appends nothing the second time to the same reader, and answers with the first" do
        aggregate_failures do
          expect(state.messages.map { |m| [m["to"], m["command"]] }).to eq([%w[luke-backend 01JM], %w[rey-frontend 01JM]])
          expect(again["number"]).to eq(1)
          expect(schema.validate(written).map { |e| e["error"] }).to eq([])
        end
      end
    end
  end

  describe "#state!" do
    it "records the state the folder was moved to" do
      state.state!(:ready_for_review)
      expect(state.state).to eq("ready_for_review")
    end
  end

  describe "#stranded" do
    before do
      state.stage!(agent: "luke-backend", round: 1, status: "Started", run: { "pid" => 999_999, "host" => Socket.gethostname })
      state.stage!(agent: "rey-frontend", round: 1, status: "Started", run: { "pid" => Process.pid, "host" => Socket.gethostname })
      state.stage!(agent: "hansolo-reviewer", round: 1, status: "Completed", run: { "pid" => 999_999, "host" => Socket.gethostname })
    end

    it "reports a Started stage whose harness is gone, and not this run's own" do
      expect(state.stranded(alive: ->(_pid) { false }).map { |s| s["agent"] }).to eq(%w[luke-backend])
    end

    it "leaves a stage whose harness is still alive" do
      expect(state.stranded(alive: ->(_pid) { true })).to eq([])
    end

    it "asks the operating system by default" do
      expect(state.stranded.map { |s| s["agent"] }).to eq(%w[luke-backend])
    end
  end

  context "when two writers race" do
    before { Array.new(8) { |i| Thread.new { state.message!(from: "a", to: "b", body: "m#{i}") } }.each(&:join) }

    it "loses neither write" do
      expect(state.messages.map { |m| m["number"] }.sort).to eq((1..8).to_a)
    end
  end

  context "when the file is corrupt" do
    before { File.write(File.join(folder, "state.json"), "{nope") }

    it "says which file, rather than a bare parser error" do
      expect { state.read }.to raise_error(OpenLanes::Error, /state.json is not valid JSON/)
    end

    it "is reported by the ledger as a problem, not raised" do
      expect(OpenLanes::Plans::Ledger.read(folder, %w[plan.md]).problems.map(&:file)).to eq(["state.json"])
    end
  end

  context "when the folder is renamed" do
    let(:moved) do
      state.sign!(agent: "luke-backend", round: 1, status: "Started")
      plan = OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
      plan.rename_to(OpenLanes::Plans.status(:building_ui))
      described_class.for(plan.feature.path)
    end

    it "moves with it, and records the new state" do
      expect([moved.signatures.size, moved.state]).to eq([1, "building_ui"])
    end
  end

  describe "last-known-state" do
    def entry(source, round, **) = OpenLanes::Plans::LastKnownState.new(source:, round:, status: "Interrupted", **)

    it "is empty when no agent was ever interrupted" do
      expect([state.last_known_states, state.last_known("luke-backend")]).to eq([{}, nil])
    end

    it "keeps one entry per agent, the last one written" do
      state.record_last_known("luke-backend", entry("agent", 1, next_step: "first"))
      state.record_last_known("luke-backend", entry("agent", 3, next_step: "third"))

      aggregate_failures do
        expect(written["last-known-state"].keys).to eq(["luke-backend"])
        expect(state.last_known("luke-backend").next_step).to eq("third")
      end
    end

    it "keeps the agent entry when the harness writes for the same round" do
      state.record_last_known("luke-backend", entry("agent", 1, next_step: "run rspec"))
      kept = state.record_last_known("luke-backend", entry("harness", 1, note: "harness died"))

      aggregate_failures do
        expect(kept.source).to eq("agent")
        expect(state.last_known("luke-backend").next_step).to eq("run rspec")
      end
    end

    it "lets an agent entry replace a harness one" do
      state.record_last_known("rey-frontend", entry("harness", 1, note: "harness died"))
      state.record_last_known("rey-frontend", entry("agent", 1, done: ["F1"]))

      expect(state.last_known("rey-frontend").source).to eq("agent")
    end

    it "refuses an agent name that is not one token" do
      expect { state.record_last_known("two words", entry("agent", 1)) }.to raise_error(OpenLanes::Error, /agent name/)
    end

    it "writes both shapes in a form the schema accepts" do
      state.record_last_known("luke-backend",
        entry("agent", 1, done: ["B1"], remaining: ["B2"], next_step: "go", files_touched: ["a.rb"]))
      state.record_last_known("rey-frontend", entry("harness", 1, note: "harness died"))

      expect(schema.validate(written).map { |e| e["error"] }).to eq([])
    end

    %w[pid tokens exit].each do |field|
      it "rejects an entry carrying machine detail: #{field}" do
        state.record_last_known("luke-backend", entry("agent", 1))
        data = written
        data["last-known-state"]["luke-backend"][field] = 1

        expect(schema.validate(data).to_a).not_to be_empty
      end
    end

    it "accepts a document written before the section existed" do
      state.sign!(agent: "luke-backend", round: 1, status: "Started")

      aggregate_failures do
        expect(written).not_to have_key("last-known-state")
        expect(schema.validate(written).to_a).to be_empty
      end
    end
  end
end
