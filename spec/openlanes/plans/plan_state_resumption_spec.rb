# frozen_string_literal: true

require "json_schemer"

# M1: a round carries on the session its agent's previous round ran in, but
# only when the plan has stayed where that round left it and the round runs
# in the same checkout. Each context below is one branch of that decision.
RSpec.describe OpenLanes::Plans::PlanState, :tree do
  subject(:decision) { state.resumption(agent: "luke-backend", state: "building", root:) }

  let(:state) { described_class.for(folder) }
  let(:root) { "/work/checkout" }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => spec_body, "plan.md" => "## U1" } }
    path
  end
  let(:schema) { JSONSchemer.schema(Pathname.new(described_class::SCHEMA_PATH)) }

  def round(number, at:, agent: "luke-backend", **fields)
    state.stage!(agent:, round: number, status: "Interrupted", started_at: at, **fields)
  end

  context "when the agent has never run" do
    it "starts fresh, saying no session was recorded" do
      expect(decision).to have_attributes(session: nil, reason: "no session recorded for luke-backend")
    end
  end

  context "when the last round left the plan in this state, in this checkout" do
    before { round(1, at: "2026-10-16T10:00:00Z", from: "planned", to: "building", session: "sess-1", cwd: root) }

    it "resumes its session" do
      expect([decision.resume?, decision.session]).to eq([true, "sess-1"])
    end

    it "writes a document the schema accepts" do
      expect(schema.validate(JSON.parse(File.read(state.path))).map { |e| e["error"] }).to eq([])
    end
  end

  context "when there are several rounds" do
    before do
      round(1, at: "2026-10-16T10:00:00Z", to: "building", session: "sess-1", cwd: root)
      round(2, at: "2026-10-16T11:00:00Z", to: "building", session: "sess-2", cwd: root)
      round(1, at: "2026-10-16T09:00:00Z", agent: "rey-frontend", to: "building", session: "other", cwd: root)
    end

    it "resumes the latest one of its own" do
      expect(decision.session).to eq("sess-2")
    end
  end

  context "when the last round moved the plan to another state" do
    before { round(1, at: "2026-10-16T10:00:00Z", to: "reviewing", session: "sess-1", cwd: root) }

    it "starts fresh, naming where it went" do
      expect(decision).to have_attributes(session: nil, reason: "the plan moved to reviewing after round 1 (sess-1)")
    end
  end

  context "when another agent moved the plan away and back since" do
    before do
      round(1, at: "2026-10-16T10:00:00Z", to: "building", session: "sess-1", cwd: root)
      round(1, at: "2026-10-16T11:00:00Z", agent: "hansolo-reviewer", from: "building", to: "reviewing")
    end

    it "starts fresh" do
      expect(decision).to have_attributes(session: nil, reason: "the plan moved to reviewing since round 1 (sess-1)")
    end
  end

  context "when the last round never settled" do
    before { round(1, at: "2026-10-16T10:00:00Z", session: "sess-1", cwd: root) }

    it "starts fresh" do
      expect(decision).to have_attributes(session: nil, reason: "round 1 (sess-1) never settled")
    end
  end

  context "when the last round ran in another checkout" do
    before { round(1, at: "2026-10-16T10:00:00Z", to: "building", session: "sess-1", cwd: "/elsewhere") }

    it "starts fresh, since claude finds a session only from where it ran" do
      expect(decision).to have_attributes(session: nil, reason: "session sess-1 ran in /elsewhere, not #{root}")
    end
  end

  context "when the last round recorded no checkout" do
    before { round(1, at: "2026-10-16T10:00:00Z", to: "building", session: "sess-1") }

    it "starts fresh" do
      expect(decision.reason).to eq("session sess-1 ran in an unrecorded checkout, not #{root}")
    end
  end

  describe "#stage! with reset" do
    before do
      round(1, at: "2026-10-16T10:00:00Z", to: "building", session: "sess-1", cwd: root)
      state.stage!(agent: "luke-backend", round: 1, reset: true, status: "Started", started_at: "2026-10-17T10:00:00Z")
    end

    it "drops what an earlier run's round of the same number left behind" do
      expect(state.stages.first.keys).to contain_exactly("agent", "round", "status", "started_at")
    end
  end
end
