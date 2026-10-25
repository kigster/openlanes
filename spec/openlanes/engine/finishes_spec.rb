# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Finishes, :tree do
  subject(:finishes) { described_class.new(runner:, clock:) }

  let(:clock) { OpenLanes::Clock::Fake.new(now: Time.utc(2026, 10, 24, 12)) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:runner) { instance_double(OpenLanes::Engine::Runner, tree:, dry_run?: false, foreign?: false) }

  def subject_plan(ordinal = "033.00") = tree.find(ordinal)
  def state(ordinal = "033.00") = OpenLanes::Plans::PlanState.for(subject_plan(ordinal).feature.path)

  before do
    plans do |t|
      t.plan "033.00", :ready_for_review, "merge-risk"
      t.plan "034.00", :ready_for_review, "other"
    end
  end

  it "carries over only the plan that finished last before the engine started" do
    state("033.00").finish!("approved", at: Time.utc(2026, 10, 1))
    state("034.00").finish!("merged", at: Time.utc(2026, 10, 2))

    expect(finishes.ordinals).to eq(["034.00"])
  end

  it "records a finish in state.json, at the clock's time, and keeps it on the board" do
    finishes.finish(subject_plan, "approved")

    aggregate_failures do
      expect(finishes.ordinals).to eq(["033.00"])
      expect(state.finished.at).to eq(Time.utc(2026, 10, 24, 12))
    end
  end

  it "shows a dry run's finish without writing it" do
    allow(runner).to receive(:dry_run?).and_return(true)
    finishes.finish(subject_plan, "approved")

    expect([finishes.ordinals, state.finished]).to eq([["033.00"], nil])
  end

  it "reads back what was written elsewhere, joining or leaving the board by it" do
    state.finish!("merged", at: clock.now)
    finishes.keep("033.00")
    joined = finishes.ordinals
    state.unfinish!
    finishes.keep("033.00")

    expect([joined, finishes.ordinals]).to eq([["033.00"], []])
  end

  it "forgets a plan an agent starts on again, on the board and in state.json" do
    finishes.finish(subject_plan, "approved")
    finishes.unfinish(subject_plan)

    expect([finishes.ordinals, state.finished]).to eq([[], nil])
  end
end
