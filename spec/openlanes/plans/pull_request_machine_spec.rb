# frozen_string_literal: true

# P2 in docs/decisions/decisions-on-merge-risk-assessment.md is the source:
# a pull request's state is its review label, read off GitHub, never stored.
RSpec.describe OpenLanes::Plans::PullRequestMachine do
  def pull(state = "open") = OpenLanes::Plans::PullRequest.new(number: "#42", title: "[001.00]", url: "https://github.com/x/y/pull/42", state:)

  def machine(*labels, state: "open") = described_class.new(pull(state), labels)

  describe ".key_for" do
    it "turns a label name into its state key" do
      expect(described_class.key_for("ready-to-merge")).to eq(:ready_to_merge)
    end
  end

  describe ".state_of" do
    it "lets GitHub's merged outrank any label" do
      expect(described_class.state_of(pull("merged"), %w[review-rejected])).to eq(:merged)
    end

    it "lets GitHub's closed outrank any label" do
      expect(described_class.state_of(pull("closed"), %w[ready-to-merge])).to eq(:closed)
    end

    it "reads an open pull request with no review label as unlabelled" do
      expect(described_class.state_of(pull, %w[bug])).to eq(described_class::UNLABELLED)
    end

    it "takes the label furthest along when a stale verdict sits beside a newer one" do
      expect(described_class.state_of(pull, %w[review-approved ready-for-review])).to eq(:review_approved)
    end
  end

  it "has a state for every review label, plus unlabelled, merged and closed" do
    keys = OpenLanes::Plans::ReviewLabel::ALL.map { described_class.key_for(it.name) }
    expect(described_class.aasm.states.map(&:name)).to match_array(keys + %i[unlabelled merged closed])
  end

  it "keeps the pull request it was read from" do
    expect(machine.pull.number).to eq("#42")
  end

  describe "#fire!" do
    it "walks the review spine to an automatic merge" do
      m = machine
      %i[submit start_review approve ready merge_automatically].each { m.fire!(it) }
      expect(m.key).to eq(:auto_merged)
    end

    it "returns the state it moved to" do
      expect(machine("review-in-progress").fire!(:pass_with_doubts)).to eq(:review_passed)
    end

    it "sends a rejected pull request back for review once fixed" do
      m = machine("review-in-progress")
      m.fire!(:reject)
      expect(m.fire!(:submit)).to eq(:ready_for_review)
    end

    it "lets a person reject a pull request they were asked to merge" do
      expect(machine("merge-manually").fire!(:reject)).to eq(:review_rejected)
    end

    it "takes a rejected pull request whose fixes arrived to review-addressed, and back into review (U1)" do
      aggregate_failures do
        expect(machine("review-rejected").fire!(:address)).to eq(:review_addressed)
        expect(machine("review-vulnerability").fire!(:address)).to eq(:review_addressed)
        expect(machine("review-addressed").fire!(:start_review)).to eq(:review_in_progress)
        expect(machine("review-approved").may?(:address)).to be(false)
      end
    end

    it "reads review-addressed over a stale review-rejected left beside it" do
      expect(machine("review-rejected", "review-addressed").key).to eq(:review_addressed)
    end

    it "flags a vulnerability from review" do
      expect(machine("review-in-progress").fire!(:flag_vulnerability)).to eq(:review_vulnerability)
    end

    it "parks a risky pull request for a person" do
      expect(machine("ready-to-merge").fire!(:leave_for_a_person)).to eq(:merge_manually)
    end

    it "records a merge or a close made on GitHub" do
      expect(machine("review-approved").fire!(:merged)).to eq(:merged)
      expect(machine("ready-for-review").fire!(:close)).to eq(:closed)
    end

    it "refuses a move outside the topology, naming the pull request and the state" do
      expect { machine("ready-for-review").fire!(:merge_automatically) }
        .to raise_error(described_class::Refused, "PR #42 is ready_for_review; merge_automatically does not apply")
    end

    it "refuses to close a pull request that was merged automatically" do
      expect(machine("auto-merged").may?(:close)).to be(false)
    end
  end

  describe "#complete?" do
    it "is true once deploy-assessor's verdict has been acted on" do
      expect(machine("auto-merged")).to be_complete
      expect(machine("merge-manually")).to be_complete
    end

    it "is false before then" do
      expect(machine("ready-to-merge")).not_to be_complete
    end
  end
end
