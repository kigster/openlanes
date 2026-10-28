# frozen_string_literal: true

# The real `.plans` tree, the real GitHub seam and the real Vcs::Review,
# answered by the fake `gh`: what is under test is what lands on disk and on
# the pull request, which a stubbed seam would only echo.
RSpec.describe OpenLanes::Arbitration::Effects, :fake_gh, :tree do
  subject(:effects) { described_class.new(tree_dir: plans_root, github: OpenLanes::Vcs::GitHub.new) }

  let(:state_key) { :rejected }
  let(:labels_now) { %w[review-rejected] }
  let(:agents) { OpenLanes::Agents::Registry.new }

  before do
    plans { |t| t.plan "015.00", state_key, "arbiter", files: { "spec.md" => spec_body, "plan.md" => "## U1" }, prs: [t.open(7, "Arbiter")] }
    edit_gh do |gh|
      gh["labels"] = OpenLanes::Plans::ReviewLabel.known
      gh["prs"] = { "7" => gh_pr(title: "Arbiter", url: "https://github.com/example/repo/pull/7", labels: labels_now) }
    end
  end

  def plan = OpenLanes::Plans::Tree.new(dir: plans_root).find("015.00")
  def labels = gh.dig("prs", "7", "labels")
  def comments = gh.dig("prs", "7", "comments").map { it["body"] }
  def mail_to = OpenLanes::Plans::PlanState.for(plan.feature.path).messages.map { it["to"] }
  def rulings = OpenLanes::Plans::PlanState.for(plan.feature.path).rulings

  def ruling(kind, outcome, struck: [], critical: [], reason: "Because the spec says so.", pr: 7) # rubocop:disable Naming/MethodParameterName -- the ruling's own key
    OpenLanes::Arbitration::Ruling.new(kind:,
      pr:,
      outcome:,
      struck:,
      critical:,
      winner: kind == "dispute" ? outcome : nil,
      reason:)
  end

  def apply(kind, outcome, **) = effects.apply(plan:, ruling: ruling(kind, outcome, **), trigger: kind, round: 2, appellant: "backend-coder")

  describe "cap / go" do
    it "sets ready-to-merge, sends the plan to 🟢, records one ruling and posts one comment" do
      result = apply("cap", "go")

      aggregate_failures do
        expect(result.to).to eq(:ready_for_review)
        expect(plan.status.key).to eq(:ready_for_review)
        expect(labels).to include("ready-to-merge")
        expect(rulings.map { it.values_at("kind", "outcome", "round") }).to eq([["cap", "go", 2]])
        expect(comments).to match([a_string_starting_with("⚖️ Ruling (cap): go").and(including("> Because the spec says so."))])
        expect(gh_calls.count { it.first(2) == %w[pr comment] }).to eq(1)
      end
    end

    it "leaves label and plan alone while CI is red, and says so on the PR" do
      edit_gh { it["prs"]["7"]["checks"] = [{ "name" => "rspec", "state" => "FAILURE", "bucket" => "fail" }] }
      result = apply("cap", "go")

      aggregate_failures do
        expect([result.to, result.label, result.refused]).to eq([nil, nil, "CI is red"])
        expect(plan.status.key).to eq(:rejected)
        expect(labels).to eq(%w[review-rejected])
        expect(comments.last).to include("Label not set: CI is red")
      end
    end
  end

  describe "cap / no_go" do
    it "keeps review-rejected, blocks the plan and quotes the ruling in blocked.md's B1" do
      apply("cap", "no_go", reason: "F1 still corrupts the ledger.")

      aggregate_failures do
        expect(plan.status.key).to eq(:blocked)
        expect(labels).to eq(%w[review-rejected])
        expect(plan.read("blocked.md")).to include("## B1", "> F1 still corrupts the ledger.", "(Recommended)")
        expect(plan.open_blocks).not_to be_empty
      end
    end
  end

  describe "appeal" do
    it "upheld: changes nothing but mails the appellant" do
      apply("appeal", "upheld")
      expect([plan.status.key, labels, mail_to]).to eq([:rejected, %w[review-rejected], %w[backend-coder]])
    end

    it "struck with nothing open: ready-to-merge, mails the appellant and staff-reviewer, and names the struck finding" do
      apply("appeal", "struck", struck: %w[F2])

      aggregate_failures do
        expect(labels).to include("ready-to-merge")
        expect(mail_to).to eq(%w[backend-coder staff-reviewer])
        expect(comments.last).to include("Struck: F2.")
        expect(plan.status.key).to eq(:rejected)
      end
    end

    it "struck with a critical finding still open: label unchanged" do
      apply("appeal", "struck", struck: %w[F2], critical: %w[F1])
      expect(labels).to eq(%w[review-rejected])
    end
  end

  describe "dispute" do
    it "mails both builders and moves nothing" do
      apply("dispute", "frontend-coder")
      expect([plan.status.key, labels, mail_to, rulings.last["winner"]])
        .to eq([:rejected, %w[review-rejected], %w[backend-coder frontend-coder], "frontend-coder"])
    end
  end

  describe "passed_check" do
    let(:state_key) { :in_review }
    let(:labels_now) { %w[review-passed] }

    it "fair: leaves the label and the plan" do
      apply("passed_check", "fair")
      expect([plan.status.key, labels, mail_to]).to eq([:in_review, %w[review-passed], []])
    end

    it "too_harsh: ready-to-merge, plan unchanged" do
      apply("passed_check", "too_harsh")
      expect([plan.status.key, labels]).to eq([:in_review, %w[ready-to-merge]])
    end

    it "too_lenient: review-rejected, 👀 → 🔴, the count one higher, and the builders told" do
      before = OpenLanes::Arbitration.counter(agents:).call(plan)
      apply("passed_check", "too_lenient")

      aggregate_failures do
        expect(labels).to include("review-rejected")
        expect(plan.status.key).to eq(:rejected)
        expect(OpenLanes::Arbitration.counter(agents:).call(plan)).to eq(before + 1)
        expect(mail_to).to eq(%w[backend-coder frontend-coder])
      end
    end

    context "when the plan is at 🟡, which has no edge to 🔴" do
      let(:state_key) { :ready_for_review }

      it "too_lenient sets no label either, so GitHub and the folder agree" do
        result = apply("passed_check", "too_lenient")

        aggregate_failures do
          expect([result.to, result.label, result.refused]).to eq([nil, nil, "a plan at ready_for_review cannot move to rejected"])
          expect([plan.status.key, labels]).to eq([:ready_for_review, %w[review-passed]])
          expect(comments.last).to include("Label not set: a plan at ready_for_review cannot move to rejected")
        end
      end
    end
  end

  describe "a ruling that names another pull request" do
    before { edit_gh { it["prs"]["8"] = gh_pr(title: "Other", url: "https://github.com/example/repo/pull/8", labels: %w[review-rejected]) } }

    it "labels and comments on neither, and says so on the plan's own" do
      result = effects.apply(plan:, ruling: ruling("cap", "go", pr: 8), trigger: "cap", round: 1)

      aggregate_failures do
        expect([result.to, result.label, result.refused]).to eq([nil, nil, "the ruling names PR #8, not this plan's #7"])
        expect([labels, gh.dig("prs", "8", "labels"), gh.dig("prs", "8", "comments")]).to eq([%w[review-rejected], %w[review-rejected], []])
        expect(comments.last).to include("Label not set: the ruling names PR #8")
        expect(rulings.last["pr"]).to eq(7)
        expect(plan.status.key).to eq(:rejected)
      end
    end

    it "takes the plan's own when the ruling names none" do
      result = effects.apply(plan:, ruling: ruling("cap", "go", pr: nil), trigger: "cap", round: 1)
      expect([result.to, labels]).to eq([:ready_for_review, %w[ready-to-merge]])
    end
  end

  it "records the round of staff-reviewer's latest review beside the struck ids" do
    OpenLanes::Plans::PlanState.for(plan.feature.path).sign!(agent: "staff-reviewer", round: 3, status: "Completed", note: "rejected 1/2")
    apply("appeal", "upheld")
    expect(rulings.last["review"]).to eq(3)
  end
end
