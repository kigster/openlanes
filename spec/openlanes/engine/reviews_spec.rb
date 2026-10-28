# frozen_string_literal: true

# A review round over a real `.plans` tree and the fake `gh`: what is under
# test is who counts, when the round is decided, and which label lands.
RSpec.describe OpenLanes::Engine::Reviews, :fake_gh, :tree do
  subject(:reviews) { described_class.new(agents:, review:) }

  let(:review) { OpenLanes::Vcs::Review.new(github: OpenLanes::Vcs::GitHub.new) }
  let(:agents_dir) { File.join(File.dirname(plans_root), "agents") }
  let(:agents) { OpenLanes::Agents::Registry.new(dir: agents_dir) }
  let(:starts) { "research" }
  let(:green) { [{ "name" => "ci", "state" => "SUCCESS", "bucket" => "pass" }] }
  let(:checks) { green }
  let(:staff) { agents.find("staff-reviewer") }
  let(:security) { agents.find("security-reviewer") }
  let(:design) { agents.find("design-reviewer") }

  def plan = OpenLanes::Plans::Tree.new(dir: plans_root).find("031.00")
  def state = OpenLanes::Plans::PlanState.for(plan.feature.path)
  def labels = gh.dig("prs", "1", "labels")
  def voted(name, note, round: 1) = reviews.vote!(plan, agents.find(name), round, note)

  before do
    FileUtils.mkdir_p(agents_dir)
    { "staff-reviewer" => "", "security-reviewer" => "starts: [research, planning]\n",
      "design-reviewer" => "starts: [research, planning]\n" }.each do |name, extra|
      File.write(File.join(agents_dir, "#{name}.md"),
        "---\nname: #{name}\nhandles: [ready_for_review, in_review]\nphase: review\nadvances_to: approved\nstarts_as: in_review\n#{extra}---\nbody")
    end
    File.write(File.join(agents_dir, "backend-coder.md"), "---\nname: backend-coder\nhandles: [in_review]\nadvances_to: rejected\n---\nbody")
    plans do |t|
      t.plan "031.00",
        :in_review,
        "three-reviewers",
        files: { "spec.md" => "---\nstarts: #{starts}\n---\n#{spec_body}" },
        prs:   [t.open(1, "Three reviewers")]
    end
    edit_gh do |data|
      data["labels"] = OpenLanes::Plans::ReviewLabel::ALL.map(&:name)
      data["prs"] = { "1" => gh_pr(title: "Three reviewers",
        url: "https://github.com/example/repo/pull/1",
        labels: %w[review-in-progress],
        checks:) }
    end
  end

  describe "#reviewers" do
    it "gives a plan that started at research all three, and no one else" do
      expect(reviews.reviewers(plan).map(&:name)).to contain_exactly("staff-reviewer", "security-reviewer", "design-reviewer")
    end

    context "when the plan starts at building" do
      let(:starts) { "building" }

      it { expect(reviews.reviewers(plan).map(&:name)).to eq(%w[staff-reviewer]) }
    end
  end

  # D10a: the counter folds a round's rejections into one by this stage.
  describe "#vote!" do
    before do
      state.update { it["moves"] = 5 }
      voted("security-reviewer", "rejected 1/2, vulnerability", round: 3)
    end

    it "records the verdict against the review round, the plan's moves when it was given" do
      expect(state.stages.last).to include("agent" => "security-reviewer", "round" => 3, "verdict" => "rejected 1/2, vulnerability", "review" => 5)
    end
  end

  describe "#decide" do
    it "reads a note with no verdict as no vote" do
      expect(reviews.decide(plan, staff, "looks fine to me")).to be_nil
    end

    context "when reviewers are still to report" do
      subject(:decision) { reviews.decide(plan, security, "passed") }

      before { voted("staff-reviewer", "great") }

      it { is_expected.to be_pending }
      it { expect(decision.pending).to eq(%w[design-reviewer]) }
      it { expect(decision.note).to eq("passed; waiting for design-reviewer") }
      it { expect(decision.target).to be_nil }
    end

    context "when the last reviewer reports" do
      subject(:decision) { reviews.decide(plan, design, last) }

      let(:last) { "great" }

      before do
        voted("staff-reviewer", "great")
        voted("security-reviewer", "passed")
      end

      it { is_expected.not_to be_pending }
      it { expect(decision.target).to eq(:approved) }
      it { expect(decision.verdict.names).to eq(%w[review-approved]) }
      it { expect(decision.note).to eq("review review-approved") }

      context "with a rejection" do
        let(:last) { "rejected 1/2: the page leaks" }

        it { expect(decision.target).to eq(:rejected) }
        it { expect(decision.verdict.names).to eq(%w[review-rejected]) }
      end

      context "with slop" do
        let(:last) { "slop" }

        it { expect(decision.target).to eq(:slop) }
      end

      context "with only one great among three" do
        let(:last) { "passed" }

        before { voted("staff-reviewer", "passed") }

        it { expect(decision.verdict.names).to eq(%w[review-passed]) }
        it { expect(decision.target).to eq(:approved) }
      end
    end

    context "when the security reviewer finds a vulnerability" do
      subject(:decision) { reviews.decide(plan, security, "rejected 1/2: an exploitable vulnerability in auth") }

      before do
        voted("staff-reviewer", "great")
        voted("design-reviewer", "great")
      end

      it { expect(decision.verdict.names).to eq(%w[review-rejected review-vulnerability]) }
    end

    context "when an earlier round's verdicts are on file" do
      subject(:decision) { reviews.decide(plan, staff, "great") }

      before do
        voted("security-reviewer", "rejected 1/2")
        voted("design-reviewer", "rejected 1/2")
        state.update { it["moves"] = 3 }
      end

      it "counts none of them" do
        expect(decision.pending).to contain_exactly("security-reviewer", "design-reviewer")
      end
    end

    context "when a reviewer reported twice in one round" do
      subject(:decision) { reviews.decide(plan, design, "great") }

      before do
        voted("staff-reviewer", "rejected 1/2")
        voted("staff-reviewer", "great", round: 2)
        voted("security-reviewer", "great")
      end

      it "counts its last" do
        expect(decision.target).to eq(:approved)
      end
    end

    context "when the plan starts at building" do
      let(:starts) { "building" }

      it "decides on staff-reviewer alone" do
        expect(reviews.decide(plan, staff, "great").verdict.names).to eq(%w[review-approved])
      end
    end
  end

  describe "#conclude" do
    subject(:concluded) { reviews.conclude(plan, decision) }

    let(:decision) { reviews.decide(plan, staff, verdict) }
    let(:starts) { "building" }
    let(:verdict) { "great" }

    it "labels the pull request with the round's verdict" do
      concluded
      expect(labels).to eq(%w[review-approved])
    end

    it { is_expected.to eq(decision) }

    context "when CI is red" do
      let(:checks) { [{ "name" => "ci", "state" => "FAILURE", "bucket" => "fail" }] }

      it "rejects instead, and says why" do
        aggregate_failures do
          expect(concluded.target).to eq(:rejected)
          expect(concluded.note).to eq("review review-approved; rejected: #1 CI is red")
          expect(labels).to eq(%w[review-rejected])
        end
      end
    end

    context "when the round rejected" do
      let(:verdict) { "rejected 1/2" }

      it "labels it rejected while CI is red too" do
        concluded
        expect(labels).to eq(%w[review-rejected])
      end
    end

    context "when gh fails" do
      before do
        allow(review).to receive(:call).and_raise(OpenLanes::Error, "gh is down")
        allow(OpenLanes::UI).to receive(:log)
      end

      it { is_expected.to eq(decision) }

      it "logs it" do
        concluded
        expect(OpenLanes::UI).to have_received(:log).with("could not label 031.00: gh is down", level: :warn, plan: "031.00")
      end
    end

    context "without a pull request to label" do
      let(:review) { nil }

      it { is_expected.to eq(decision) }
    end
  end

  describe "#started" do
    it "marks every open pull request in progress" do
      edit_gh { it["prs"]["1"]["labels"] = %w[ready-for-review] }
      reviews.started(plan)
      expect(labels).to eq(%w[review-in-progress])
    end
  end
end
