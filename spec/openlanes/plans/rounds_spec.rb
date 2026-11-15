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

    it "counts only the ones started after a grant" do
      since = Time.iso8601("2026-11-12T10:01:30+00:00")
      tail = [stage(2, status: failed, started_at: "2026-11-12T10:02:00+00:00")]
      more = described_class.new(stages: stages.first(1) + [stage(2, status: failed, started_at: "2026-11-12T10:01:00+00:00")] + tail, signatures:)
      expect(more.failed_starts("backend-coder", "building", moves: 1, count: described_class::Count.new(since:))).to eq(1)
    end

    it "excuses a failed login without breaking the run of the others" do
      login = stage(2, status: failed, note: "failed start: OAuth session expired")
      more = described_class.new(stages: stages + [login], signatures:)
      expect(more.failed_starts("backend-coder", "building", moves: 1, count: described_class::Count.new(except: /OAuth/))).to eq(2)
    end

    it "says when the latest one ended" do
      last = stage(2, status: failed, finished_at: "2026-11-12T10:09:00-08:00")
      more = described_class.new(stages: stages + [last], signatures:)
      expect(more.last_failed_start("backend-coder", "building", moves: 1)).to eq(Time.utc(2026, 11, 12, 18, 9))
    end

    it "says nothing ended when none failed" do
      expect(described_class.new(stages: [stage(1)], signatures:).last_failed_start("backend-coder", "building", moves: 1)).to be_nil
    end
  end

  context "with failed logins among the failed starts" do
    let(:login) { { status: failed, note: "failed start: OAuth session expired" } }
    let(:stages) { [stage(1, **login), stage(1, **login), stage(1, **login)] }

    it "excuses any number of them when no limit is set" do
      count = described_class::Count.new(except: /OAuth/)
      expect(rounds.failed_starts("backend-coder", "building", moves: 1, count:)).to eq(0)
    end

    it "counts them all once as many as are tolerated ran in a row" do
      count = described_class::Count.new(except: /OAuth/, tolerate: 3)
      expect(rounds.failed_starts("backend-coder", "building", moves: 1, count:)).to eq(3)
    end

    it "still excuses fewer than are tolerated" do
      count = described_class::Count.new(except: /OAuth/, tolerate: 4)
      expect(rounds.failed_starts("backend-coder", "building", moves: 1, count:)).to eq(0)
    end
  end

  # An agent that `starts_as` is picked up in one state and works in the
  # next: `from` names the first, and the round is counted for the second.
  context "with a round whose start renamed the folder" do
    let(:stages) { [stage(1, from: "planned", state: "building"), stage(2, state: "building")] }

    it "counts it for the state it worked in" do
      expect([rounds.used("backend-coder", "building", moves: 1), rounds.next("backend-coder", "building", moves: 1)])
        .to eq([2, 3])
    end

    it "does not count it for the state the plan was picked up in" do
      expect(rounds.used("backend-coder", "planned", moves: 1)).to eq(0)
    end

    it "counts a failed start on it towards the cap" do
      failing = described_class.new(stages: [stage(1, from: "planned", state: "building", status: failed)], signatures:)
      expect(failing.failed_starts("backend-coder", "building", moves: 1)).to eq(1)
    end
  end

  # What the release before wrote for the same round: `from` and `visit`,
  # and no `state`.
  context "with a renaming round written before stages named their state" do
    let(:stages) do
      [stage(1, from: "planned", to: "building", moves: 1),
       stage(2, to: "ready_for_review", moves: 2),
       stage(3, from: "planned")]
    end

    it "reads one that settled without the plan moving as worked where it left the plan" do
      expect(rounds.visit("backend-coder", "building", moves: 1).map { it["round"] }).to eq([1, 2])
    end

    it "reads one that never settled as worked where it was picked up" do
      expect(rounds.used("backend-coder", "planned", moves: 1)).to eq(1)
    end
  end

  context "with a round the harness handed back" do
    let(:stages) { [stage(1, status: "Interrupted", handed_back: true)] }

    it "spends nothing, and hands the same number out again" do
      expect([rounds.used("backend-coder", "building", moves: 1), rounds.next("backend-coder", "building", moves: 1)])
        .to eq([0, 1])
    end

    it "does not count as a failed start" do
      expect(rounds.failed_starts("backend-coder", "building", moves: 1)).to eq(0)
    end
  end

  context "with one round number run twice" do
    let(:stages) { [stage(1, status: "Interrupted"), stage(1), stage(2, status: "Interrupted"), stage(2, status: failed)] }

    it "counts each number once" do
      expect(rounds.used("backend-coder", "building", moves: 1)).to eq(1)
    end

    it "reads each round as its latest stage has it" do
      expect(rounds.visit("backend-coder", "building", moves: 1).map { it.values_at("round", "status") }).to eq([[1, "Completed"]])
    end

    it "keeps stages that carry no number apart, so the count never goes down" do
      loose = described_class.new(stages: [stage(nil), stage(nil)], signatures:)
      expect(loose.used("backend-coder", "building", moves: 1)).to eq(2)
    end
  end

  describe "#started" do
    let(:stages) do
      [stage(1, status: "Started"), stage(1, status: "Started", agent: "frontend-coder"), stage(2),
       stage(1, status: "Started", visit: 0), stage(3, status: "Interrupted", handed_back: true)]
    end

    it "lists the rounds of the visit still Started, whoever runs them" do
      expect(rounds.started("building", moves: 1).map { it["agent"] }).to eq(%w[backend-coder frontend-coder])
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

  context "when the signature and the stage carry different UTC offsets" do
    let(:stages) { [stage(1, started_at: "2026-11-01T01:30:00-07:00")] }
    let(:signatures) do
      [{ "agent" => "backend-coder", "round" => 4, "status" => "Completed", "at" => "2026-11-01T01:10:00-08:00" },
       { "agent" => "backend-coder", "round" => 7, "status" => "Completed", "at" => "not a time" }]
    end

    it "orders them by time, not as strings, and ignores a malformed one" do
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
