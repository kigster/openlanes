# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::Rounds do
  subject(:rounds) { described_class.new(stages:, signatures:) }

  let(:signatures) { [] }
  let(:failed) { OpenLanes::Plans::PlanState::FAILED_START }

  def stage(round, **fields)
    { "agent" => "backend-coder", "round" => round, "status" => "Completed", "from" => "building", "visit" => 1,
      "started_at" => "2026-11-12T10:0#{round}:00+00:00" }.merge(fields.transform_keys(&:to_s))
  end

  context "with two rounds spent in the current visit" do
    let(:stages) { [stage(1), stage(2), stage(1, agent: "frontend-coder")] }

    it "counts them per agent" do
      expect(rounds.used("backend-coder", "building", moves: 1)).to eq(2)
    end

    it "hands out the round after them" do
      expect(rounds.next("backend-coder", :building, moves: 1)).to eq(3)
    end

    it "leaves the budget less what was spent" do
      expect(rounds.left("backend-coder", "building", moves: 1, budget: 3)).to eq(1)
    end

    it "never reports fewer than zero left" do
      expect(rounds.left("backend-coder", "building", moves: 1, budget: 1)).to eq(0)
    end
  end

  context "when the plan comes back to a state it left" do
    let(:stages) { [stage(1), stage(2), stage(1, from: "built", visit: 2)] }

    it "starts the state fresh" do
      expect([rounds.used("backend-coder", "building", moves: 3), rounds.next("backend-coder", "building", moves: 3)])
        .to eq([0, 1])
    end
  end

  context "with failed starts" do
    let(:stages) { [stage(1), stage(2, status: failed), stage(2, status: failed)] }

    it "spends no round on them" do
      expect([rounds.used("backend-coder", "building", moves: 1), rounds.next("backend-coder", "building", moves: 1)])
        .to eq([1, 2])
    end

    it "counts the ones in a row that end the visit" do
      expect(rounds.failed_starts("backend-coder", "building", moves: 1)).to eq(2)
    end

    it "stops counting at a round that ran" do
      more = described_class.new(stages: stages + [stage(2)], signatures:)
      expect(more.failed_starts("backend-coder", "building", moves: 1)).to eq(0)
    end
  end

  context "with stages an older release wrote" do
    let(:stages) do
      [{ "agent" => "backend-coder", "round" => 1, "status" => "Completed", "to" => "building", "moves" => 4 },
       { "agent" => "backend-coder", "round" => 2, "status" => "Completed", "from" => "building", "to" => "built", "moves" => 5 },
       { "agent" => "backend-coder", "round" => 1, "status" => "Completed", "to" => "building", "moves" => 2 },
       { "agent" => "backend-coder", "round" => 3, "status" => "Started", "from" => "building" }]
    end

    it "reads each as the visit its to and moves imply, so the round never goes down" do
      expect(rounds.next("backend-coder", "building", moves: 4)).to eq(4)
    end

    it "does not count a stage whose from names another state" do
      expect(rounds.used("backend-coder", "built", moves: 5)).to eq(0)
    end
  end

  context "when a signature outran its stage" do
    let(:stages) { [stage(1)] }
    let(:signatures) do
      [{ "agent" => "backend-coder", "round" => 4, "status" => "Completed", "at" => "2026-11-12T10:05:00+00:00" },
       { "agent" => "backend-coder", "round" => 9, "status" => "Completed", "at" => "2026-11-11T10:05:00+00:00" }]
    end

    it "is never lower than the highest round signed in the visit" do
      expect(rounds.next("backend-coder", "building", moves: 1)).to eq(5)
    end
  end

  context "when the visit has no stage yet" do
    let(:stages) { [] }
    let(:signatures) { [{ "agent" => "backend-coder", "round" => 9, "status" => "Completed", "at" => "2026-11-12T10:05:00+00:00" }] }

    it "starts at round 1" do
      expect(rounds.next("backend-coder", "building", moves: 0)).to eq(1)
    end
  end

  describe ".from", :tree do
    it "reads the stages and signatures of a plan's state.json" do
      folder = nil
      plans { |t| folder = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work" } }
      state = OpenLanes::Plans::PlanState.for(folder)
      state.stage!(agent: "backend-coder", round: 1, reset: true, status: "Started", from: "building")
      expect(described_class.from(state).next("backend-coder", "building", moves: state.moves)).to eq(2)
    end
  end
end
