# frozen_string_literal: true

RSpec.describe OpenLanes::Live::Copilot::Report do
  subject(:report) { described_class.new(snapshot) }

  let(:query) { OpenLanes::Live::Copilot::Slash::Query }
  let(:working) do
    { "agent" => "builder", "state" => "working", "round" => 2, "model" => "opus", "remaining" => 90, "message" => "writing specs" }
  end
  let(:idle) { { "agent" => "reviewer", "state" => "waiting", "round" => 1, "model" => "sonnet", "message" => "" } }
  let(:plans) do
    [{ "ordinal" => "020.00",
       "title"   => "Tax Rule DSL",
       "status"  => { "emoji" => "🟡", "label" => "Building" },
       "cars"    => [working, idle],
       "cost"    => 1.5 },
     { "ordinal" => "021.00", "title" => "Tenancy", "status" => { "emoji" => "⭐️", "label" => "Planned" }, "cars" => [] }]
  end
  let(:run) do
    { "status" => "running", "started_at" => "2026-10-13T09:00:00Z", "agents_working" => 1, "jobs" => 4, "up" => 1200, "down" => 340, "cost" => 2.5 }
  end
  let(:snapshot) { JSON.generate("run" => run, "plans" => plans) }

  def status(plan = nil) = report.call(query.new(kind: "status", plan:))

  def stats = report.call(query.new(kind: "stats", plan: nil))

  describe "with no snapshot to read" do
    context "when no engine has written one" do
      let(:snapshot) { nil }

      it("says no engine runs, for /status") { expect(status).to eq(described_class::NOTHING) }
      it("says no engine runs, for /stats") { expect(stats).to eq(described_class::NOTHING) }
    end

    context "when what Redis holds is not JSON" do
      let(:snapshot) { "{half a snap" }

      it("answers as if there were none") { expect(status("020.00")).to eq(described_class::NOTHING) }
    end
  end

  describe "/status" do
    it "lists every plan with its state, title, agents and cost" do
      expect(status).to eq(<<~TEXT.chomp)
        2 plans on the board:
        020.00 🟡 Building · Tax Rule DSL · builder, reviewer · $1.50
        021.00 ⭐️ Planned · Tenancy · $0.00
      TEXT
    end

    context "with one plan" do
      let(:plans) { super().first(1) }

      it("counts it in the singular") { expect(status.lines.first.chomp).to eq("1 plan on the board:") }
    end

    context "with an empty board" do
      let(:plans) { [] }

      it("says so") { expect(status).to eq("No plan is on the board.") }
    end

    context "with a snapshot that names no plans at all" do
      let(:snapshot) { JSON.generate("run" => run) }

      it("reads it as an empty board") { expect(status).to eq("No plan is on the board.") }
    end

    context "with a plan that carries no status" do
      let(:plans) { [{ "ordinal" => "022.00", "title" => "Bare" }] }

      it("still draws its line") { expect(status.lines.last).to eq("022.00   · Bare · $0.00") }
    end
  end

  describe "/status NNN" do
    it "tells each agent's state, round, model, time left and last word" do
      expect(status("020.00")).to eq(<<~TEXT.chomp)
        020.00 🟡 Building · Tax Rule DSL · builder, reviewer · $1.50
          builder: working, round 2, opus, 90s left · writing specs
          reviewer: waiting, round 1, sonnet
      TEXT
    end

    it "says when no agent is on the plan" do
      expect(status("021.00")).to eq("021.00 ⭐️ Planned · Tenancy · $0.00\n  no agent is working on it")
    end

    it("says when the plan is not on the board") { expect(status("099.00")).to eq("099.00 is not on the board.") }
  end

  describe "/stats" do
    it "tells the run, its agents, the board, the tokens and the cost" do
      expect(stats).to eq(<<~TEXT.chomp)
        Run running, since 2026-10-13T09:00:00Z
        agents working: 1 of 4
        plans on the board: 2
        tokens: 1200 in, 340 out
        cost: $2.50
      TEXT
    end

    context "with a snapshot that carries no run" do
      let(:snapshot) { JSON.generate("plans" => []) }

      it "draws zeroes and never raises" do
        expect(stats).to eq("Run \nagents working: 0 of 0\nplans on the board: 0\ntokens: 0 in, 0 out\ncost: $0.00")
      end
    end
  end
end
