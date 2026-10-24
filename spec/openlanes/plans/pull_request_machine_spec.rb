# frozen_string_literal: true

# P2's pull-request machine, with 036.00's edges: the builders' answer to a
# rejection goes through responding-to-review and review-responded, and a
# conflict with main takes ready-to-merge off without re-running review.
RSpec.describe OpenLanes::Plans::PullRequestMachine do
  let(:pull) { OpenLanes::Plans::PullRequest.new(number: "7", title: "t", url: "https://github.com/o/r/pull/7", state: "open") }

  def machine(*labels) = described_class.new(pull, labels)

  describe "the response to a rejection" do
    it "walks rejected → responding → responded → ready-for-review" do
      m = machine("review-rejected")

      expect([m.fire!(:respond), m.fire!(:responded), m.fire!(:submit)])
        .to eq(%i[responding_to_review review_responded ready_for_review])
    end

    it "starts the response from a vulnerability too" do
      expect(machine("review-rejected", "review-vulnerability").fire!(:respond)).to eq(:responding_to_review)
    end

    it "no longer submits a rejected pull request straight back to review" do
      expect(machine("review-rejected").may?(:submit)).to be(false)
    end

    it "still submits an unlabelled one" do
      expect(machine.fire!(:submit)).to eq(:ready_for_review)
    end

    it "refuses review_responded → review_in_progress: it goes back through ready-for-review" do
      expect { machine("review-responded").fire!(:start_review) }
        .to raise_error(described_class::Refused, /PR #7 is review_responded; start_review does not apply/)
    end

    it "refuses responded before the builders started" do
      expect(machine("review-rejected").may?(:responded)).to be(false)
    end
  end

  describe "conflict" do
    it "takes ready-to-merge back to review-approved" do
      expect(machine("ready-to-merge").fire!(:conflict)).to eq(:review_approved)
    end

    it "takes merge-manually back to review-approved" do
      expect(machine("merge-manually").fire!(:conflict)).to eq(:review_approved)
    end

    it "never moves a pull request back into review" do
      targets = described_class.aasm.events.find { it.name == :conflict }.transitions.map(&:to).uniq

      expect(targets).to eq([:review_approved])
    end

    it "does not apply before chewie or after the engine merged it" do
      aggregate_failures do
        expect(machine("review-approved").may?(:conflict)).to be(false)
        expect(machine("auto-merged").may?(:conflict)).to be(false)
      end
    end

    it "leaves reject reaching back from ready-to-merge, for a person's rejection" do
      expect(machine("ready-to-merge").fire!(:reject)).to eq(:review_rejected)
    end
  end

  describe ".state_of" do
    it "never reads rebase-in-progress as a state" do
      aggregate_failures do
        expect(described_class.state_of(pull, ["rebase-in-progress"])).to eq(:unlabelled)
        expect(described_class.state_of(pull, %w[rebase-in-progress review-approved])).to eq(:review_approved)
      end
    end

    it "lets GitHub's merged state outrank any label" do
      merged = pull.with(state: "merged")

      expect(described_class.state_of(merged, %w[ready-to-merge])).to eq(:merged)
    end

    it "answers closed for a pull request that is neither open nor merged" do
      expect(described_class.state_of(pull.with(state: "closed"), [])).to eq(:closed)
    end
  end

  it "closes a pull request that is responding to review" do
    expect(machine("responding-to-review").fire!(:close)).to eq(:closed)
  end

  it "says when palpatine's verdict has been acted on" do
    aggregate_failures do
      expect(machine("merge-manually")).to be_complete
      expect(machine("review-responded")).not_to be_complete
    end
  end
end
