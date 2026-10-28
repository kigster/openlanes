# frozen_string_literal: true

RSpec.describe OpenLanes::Arbitration::Counter, :tree do
  subject(:counter) { OpenLanes::Arbitration.counter(agents: OpenLanes::Agents::Registry.new) }

  before { plans { |t| t.plan "015.00", :rejected, "arbiter", files: { "spec.md" => spec_body, "plan.md" => "## U1" } } }

  let(:start) { Time.now - 3600 }

  def plan = OpenLanes::Plans::Tree.new(dir: plans_root).find("015.00")
  def state = OpenLanes::Plans::PlanState.for(plan.feature.path)
  def sign(agent, note, minute) = state.sign!(agent:, round: 1, status: "Completed", note:, at: start + (minute * 60))

  def rule(kind, outcome, minute, critical: [])
    state.rule!(kind:,
      pr: 1,
      round: 1,
      outcome:,
      findings: { struck: %w[F2], critical: },
      winner: nil,
      reason: "r",
      trigger: kind,
      at: start + (minute * 60))
  end

  it "counts staff-reviewer's and verifier's rejections, and nothing else" do
    sign("staff-reviewer", "rejected 1/2", 1)
    sign("verifier", "rejected: CI is red; signed by harness", 2)
    sign("staff-reviewer", "approved, nothing to reject", 3)
    sign("backend-coder", "rejected the idea", 4)
    expect(counter.call(plan)).to eq(2)
  end

  context "with three reviewers (plan 031, D10a)" do
    def voted(agent, note, review) = state.stage!(agent:, round: 1, status: "Completed", verdict: note, review:)

    before do
      %w[staff-reviewer security-reviewer design-reviewer].each_with_index do |agent, minute|
        sign(agent, "rejected 1/2", minute)
        voted(agent, "rejected 1/2", 4)
      end
    end

    it "counts the rejections of one review round once" do
      expect(counter.call(plan)).to eq(1)
    end

    it "counts the next round's again" do
      state.stage!(agent: "staff-reviewer", round: 2, status: "Completed", verdict: "rejected 2/2", review: 8)
      state.sign!(agent: "staff-reviewer", round: 2, status: "Completed", note: "rejected 2/2", at: start + 600)
      expect(counter.call(plan)).to eq(2)
    end
  end

  it "starts again after a cap ruling" do
    sign("staff-reviewer", "rejected 1/2", 1)
    sign("staff-reviewer", "rejected 2/2", 2)
    rule("cap", "go", 3)
    sign("verifier", "rejected: still red", 4)
    expect(counter.call(plan)).to eq(1)
  end

  it "skips a rejection whose findings were all struck" do
    sign("staff-reviewer", "rejected 1/2", 1)
    sign("staff-reviewer", "rejected 2/2", 2)
    rule("appeal", "struck", 3)
    expect(counter.call(plan)).to eq(1)
  end

  it "still counts a rejection a struck appeal left a critical finding in" do
    sign("staff-reviewer", "rejected 1/2", 1)
    rule("appeal", "struck", 2, critical: %w[F1])
    expect(counter.call(plan)).to eq(1)
  end

  it "counts a too_lenient ruling as one rejection more" do
    sign("staff-reviewer", "rejected 1/2", 1)
    rule("passed_check", "too_lenient", 2)
    expect(counter.call(plan)).to eq(2)
  end
end
