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

  it "lets a stage name every adapter the harness knows, and no other" do
    stage = JSON.parse(File.read(described_class::SCHEMA_PATH)).dig("properties", "stages", "items", "properties", "adapter", "enum")
    expect(stage).to eq(OpenLanes::Adapters.names)
  end

  it "reads as an empty document before anything is written" do
    expect([state.exist?, state.stages, state.signatures, state.messages]).to eq([false, [], [], []])
  end

  describe "#stage!" do
    before do
      state.stage!(agent: "backend-coder",
        round: 1,
        status: "Started",
        adapter: "claude",
        model: "opus",
        effort: "high",
        started_at: Time.now.iso8601,
        run: { "pid" => 42, "host" => "box" })
      state.stage!(agent: "backend-coder",
        round: 1,
        status: "Completed",
        up: 10,
        down: 5,
        seconds: 1.5,
        finished_at: Time.now.iso8601)
    end

    it "keeps one record per agent per round, from dispatch to settlement" do
      expect(state.stages.map { |s| s.values_at("agent", "round", "status", "model") })
        .to eq([["backend-coder", 1, "Completed", "opus"]])
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
      state.sign!(agent: "spec-writer", round: 1, status: "Completed", next_agent: "planner", note: "done")
      state.ledger
    end

    it "records a signature the ledger reads back as an entry with its handoff" do
      expect([reading.entries.first.to_h.slice(:agent, :status, :round, :note, :file),
              OpenLanes::Plans::Ledger.handoff_after(reading, reading.entries.first)&.next])
        .to eq([{ agent: "spec-writer", status: "Completed", round: 1, note: "done", file: "state.json" },
                "planner"])
    end

    it "refuses a status outside the ledger's vocabulary" do
      expect { state.sign!(agent: "x", round: 1, status: "Done") }.to raise_error(OpenLanes::Error, /status must be/)
    end

    it "refuses a handoff after anything but Completed" do
      expect { state.sign!(agent: "x", round: 1, status: "Blocked", next_agent: "y") }
        .to raise_error(OpenLanes::Error, /only a Completed/)
    end

    it "refuses an agent name with spaces" do
      expect { state.sign!(agent: "backend-coder backend", round: 1, status: "Started") }.to raise_error(OpenLanes::Error)
    end

    it "is read by the ledger with the plan's documents" do
      state.sign!(agent: "backend-coder", round: 1, status: "Completed")
      expect(OpenLanes::Plans::Ledger.last_for(OpenLanes::Plans::Ledger.read(folder, %w[plan.md]), "backend-coder").file)
        .to eq("state.json")
    end
  end

  describe "#rule!" do
    it "reads as no rulings on a state.json written before rulings existed" do
      state.sign!(agent: "backend-coder", round: 1, status: "Started")
      expect([written.key?("rulings"), state.rulings]).to eq([false, []])
    end

    context "with one ruling recorded" do
      before do
        state.rule!(kind: "appeal",
          pr: 26,
          round: 2,
          outcome: "struck",
          findings: { struck: %w[F2], critical: [] },
          winner: nil,
          reason: "F2 asks for a test the spec rules out",
          trigger: "appeal")
      end

      it "writes it back as a dated entry the schema accepts" do
        aggregate_failures do
          expect(state.rulings.map { it.values_at("kind", "pr", "round", "outcome", "trigger") })
            .to eq([["appeal", 26, 2, "struck", "appeal"]])
          expect(state.rulings.first["findings"]).to eq("struck" => %w[F2], "critical" => [])
          expect(Time.iso8601(state.rulings.first["at"])).to be_a(Time)
          expect(schema.validate(written).map { |e| e["error"] }).to eq([])
        end
      end
    end

    it "is refused by the schema with an unknown kind" do
      state.rule!(kind: "drift", pr: nil, round: nil, outcome: "x", findings: nil, winner: nil, reason: "r", trigger: "t")
      expect(schema.validate(written).to_a).not_to be_empty
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
        state.message!(from: "human", to: "backend-coder", body: "one", command: "01JM")
        state.message!(from: "human", to: "frontend-coder", body: "one", command: "01JM")
      end

      let!(:again) { state.message!(from: "human", to: "backend-coder", body: "one", command: "01JM") }

      it "appends nothing the second time to the same reader, and answers with the first" do
        aggregate_failures do
          expect(state.messages.map { |m| [m["to"], m["command"]] }).to eq([%w[backend-coder 01JM], %w[frontend-coder 01JM]])
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

  describe "#conversion!" do
    let(:digest) { Digest::SHA256.hexdigest("Should I rebase?") }

    before do
      state.conversion!(question: 2, digest:, original: "Should I rebase?", model: "anthropic/claude-haiku-5.5", outcome: "converted")
    end

    it "keeps the agent's words and the digest that stops a second call" do
      aggregate_failures do
        expect(state.conversions.first).to include("question" => 2, "original" => "Should I rebase?", "outcome" => "converted")
        expect([state.converted?(digest), state.converted?("0" * 64)]).to eq([true, false])
        expect(schema.validate(written).map { |e| e["error"] }).to eq([])
      end
    end

    it "records a rejection with its reason" do
      state.conversion!(question: 2, digest: "f" * 64, original: "x", model: "m", outcome: "rejected", note: "1 option")
      expect([state.conversions.last["note"], schema.validate(written).to_a]).to eq(["1 option", []])
    end
  end

  describe "#resume_anyway!" do
    let(:now) { Time.now }

    it "is not resumed until someone says so" do
      expect([state.resume_until, state.resumed?(now:)]).to eq([nil, false])
    end

    it "lifts the halt until the expiry, then lets it lapse with nothing to undo" do
      state.resume_anyway!(till: now + 86_400)

      aggregate_failures do
        expect(state.resume_until.to_i).to eq((now + 86_400).to_i)
        expect(state.resumed?(now:)).to be(true)
        expect(state.resumed?(now: now + 86_401)).to be(false)
        expect(schema.validate(written).map { |e| e["error"] }).to eq([])
      end
    end
  end

  describe "#finish!" do
    let(:approved_at) { Time.utc(2026, 10, 18, 12) }
    let(:merged_at) { approved_at + 600 }

    it "is nil for a plan that never finished" do
      expect(state.finished).to be_nil
    end

    it "keeps how and when, in a form the schema accepts" do
      state.finish!("approved", at: approved_at)

      aggregate_failures do
        expect(state.finished).to eq(described_class::Finished.new(kind: "approved", at: approved_at))
        expect(written["finished"]).to eq("kind" => "approved", "at" => "2026-10-18T12:00:00Z")
        expect(schema.validate(written).map { |e| e["error"] }).to eq([])
      end
    end

    it "lets a merge replace an approval" do
      state.finish!("approved", at: approved_at)
      state.finish!(:merged, at: merged_at)

      expect(state.finished).to eq(described_class::Finished.new(kind: "merged", at: merged_at))
    end

    it "keeps the first merge's time and writes nothing when the watch reports it again" do
      state.finish!("merged", at: merged_at)
      before = File.read(state.path)

      aggregate_failures do
        expect(state.finish!("merged", at: merged_at + 15).at).to eq(merged_at)
        expect(state.finish!("approved", at: merged_at + 30).kind).to eq("merged")
        expect(File.read(state.path)).to eq(before)
      end
    end

    it "takes a second approval's time, as after a rejection and a rebuild" do
      state.finish!("approved", at: approved_at)
      state.finish!("approved", at: merged_at)

      expect(state.finished.at).to eq(merged_at)
    end

    it "refuses a kind it does not know" do
      expect { state.finish!("shipped") }.to raise_error(OpenLanes::Error, /approved or merged/)
    end

    it "is forgotten by #unfinish!, which writes nothing when there is nothing to forget" do
      state.unfinish!
      existed = state.exist?
      state.finish!("approved", at: approved_at)
      state.unfinish!

      aggregate_failures do
        expect(existed).to be(false)
        expect(state.finished).to be_nil
        expect(written).not_to have_key("finished")
      end
    end

    it "rejects a record the schema does not know" do
      state.finish!("approved", at: approved_at)
      data = written.merge("finished" => { "kind" => "shipped", "at" => "2026-10-18T12:00:00Z" })

      expect(schema.validate(data).to_a).not_to be_empty
    end
  end

  describe "a stage written by this release" do
    it "carries no run, and the schema accepts it" do
      state.stage!(agent: "backend-coder", round: 1, status: "Started", started_at: Time.now.iso8601)
      aggregate_failures do
        expect(written["stages"].flat_map(&:keys)).not_to include("run")
        expect(schema.validate(written).map { |e| e["error"] }).to eq([])
        expect(state.stranded(alive: ->(_pid) { false })).to eq([])
      end
    end
  end

  # Stages an older release wrote carry `run`; a crash under that layout
  # must still resume.
  describe "#stranded" do
    before do
      state.stage!(agent: "backend-coder", round: 1, status: "Started", run: { "pid" => 999_999, "host" => Socket.gethostname })
      state.stage!(agent: "frontend-coder", round: 1, status: "Started", run: { "pid" => Process.pid, "host" => Socket.gethostname })
      state.stage!(agent: "staff-reviewer", round: 1, status: "Completed", run: { "pid" => 999_999, "host" => Socket.gethostname })
    end

    it "reports a Started stage whose harness is gone, and not this run's own" do
      expect(state.stranded(alive: ->(_pid) { false }).map { |s| s["agent"] }).to eq(%w[backend-coder])
    end

    it "leaves a stage whose harness is still alive" do
      expect(state.stranded(alive: ->(_pid) { true })).to eq([])
    end

    it "asks the operating system by default" do
      expect(state.stranded.map { |s| s["agent"] }).to eq(%w[backend-coder])
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
      state.sign!(agent: "backend-coder", round: 1, status: "Started")
      plan = OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
      plan.rename_to(OpenLanes::Plans.status(:building_ui))
      described_class.for(plan.feature.path)
    end

    it "moves with it, and records the new state" do
      expect([moved.signatures.size, moved.state]).to eq([1, "building_ui"])
    end

    it "says in the log which plan moved, from which state to which" do
      heard = []
      tap = OpenLanes::UI.tap_log(->(message, fields) { heard << [message, fields] })
      moved
      OpenLanes::UI.untap_log(tap)

      expect(heard).to include([match(/\Amoved: .+ → #{Regexp.escape(OpenLanes::Plans.status(:building_ui).to_s)}\z/),
                                include(plan: "001.00")])
    end
  end

  describe "last-known-state" do
    def entry(source, round, **) = OpenLanes::Plans::LastKnownState.new(source:, round:, status: "Interrupted", **)

    it "is empty when no agent was ever interrupted" do
      expect([state.last_known_states, state.last_known("backend-coder")]).to eq([{}, nil])
    end

    it "keeps one entry per agent, the last one written" do
      state.record_last_known("backend-coder", entry("agent", 1, next_step: "first"))
      state.record_last_known("backend-coder", entry("agent", 3, next_step: "third"))

      aggregate_failures do
        expect(written["last-known-state"].keys).to eq(["backend-coder"])
        expect(state.last_known("backend-coder").next_step).to eq("third")
      end
    end

    it "keeps the agent entry when the harness writes for the same round" do
      state.record_last_known("backend-coder", entry("agent", 1, next_step: "run rspec"))
      kept = state.record_last_known("backend-coder", entry("harness", 1, note: "harness died"))

      aggregate_failures do
        expect(kept.source).to eq("agent")
        expect(state.last_known("backend-coder").next_step).to eq("run rspec")
      end
    end

    it "lets an agent entry replace a harness one" do
      state.record_last_known("frontend-coder", entry("harness", 1, note: "harness died"))
      state.record_last_known("frontend-coder", entry("agent", 1, done: ["F1"]))

      expect(state.last_known("frontend-coder").source).to eq("agent")
    end

    it "refuses an agent name that is not one token" do
      expect { state.record_last_known("two words", entry("agent", 1)) }.to raise_error(OpenLanes::Error, /agent name/)
    end

    it "writes both shapes in a form the schema accepts" do
      state.record_last_known("backend-coder",
        entry("agent", 1, done: ["B1"], remaining: ["B2"], next_step: "go", files_touched: ["a.rb"]))
      state.record_last_known("frontend-coder", entry("harness", 1, note: "harness died"))

      expect(schema.validate(written).map { |e| e["error"] }).to eq([])
    end

    %w[pid tokens exit].each do |field|
      it "rejects an entry carrying machine detail: #{field}" do
        state.record_last_known("backend-coder", entry("agent", 1))
        data = written
        data["last-known-state"]["backend-coder"][field] = 1

        expect(schema.validate(data).to_a).not_to be_empty
      end
    end

    it "accepts a document written before the section existed" do
      state.sign!(agent: "backend-coder", round: 1, status: "Started")

      aggregate_failures do
        expect(written).not_to have_key("last-known-state")
        expect(schema.validate(written).to_a).to be_empty
      end
    end
  end
end
