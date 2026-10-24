# frozen_string_literal: true

# Decisions U1 to U4: a real `.plans` tree, and a double for the GitHub seam,
# so what is under test is which pull requests are asked about, and which
# labels, comments and rebases reach GitHub.
RSpec.describe OpenLanes::Engine::PullRequestUpkeep, :tree do
  subject(:upkeep) { described_class.new(github:, clock: -> { now }) }

  let(:github) { instance_double(OpenLanes::Vcs::GitHub) }
  let(:now) { Time.utc(2026, 10, 24, 12) }
  let(:labels) { OpenLanes::Plans::ReviewLabel }
  let(:url) { "https://github.com/example/repo/pull/1" }
  let(:live) { { number: 1, open: true, labels: %w[ready-to-merge], merge_state: "CLEAN" } }

  def plan = OpenLanes::Plans::Tree.new(dir: plans_root).find("033.00")
  def subjects = OpenLanes::Plans::Tree.new(dir: plans_root).subjects

  before do
    plans { |t| t.plan "033.00", :completed, "merge-risk", prs: [t.open(1, "Part 1")] }
    allow(github).to receive_messages(branch_head: "main-1", pull_request: live, swap_label: [], comment: nil, update_branch: nil)
  end

  describe "#address" do
    let(:rejected_at) { Time.utc(2026, 10, 19, 10, 9, 11) }

    before do
      allow(github).to receive_messages(open_pulls_labelled: { 93 => %w[review-rejected] }, labelled_at: rejected_at)
    end

    it "labels a rejected pull request review-addressed once a commit lands after the rejection (#93)" do
      allow(github).to receive(:head_committed_at).and_return(Time.utc(2026, 10, 19, 15, 45, 48))

      aggregate_failures do
        expect(upkeep.address).to eq(["PR #93 review-addressed: committed 2026-10-19T15:45:48Z, after the rejection at 2026-10-19T10:09:11Z"])
        expect(github).to have_received(:swap_label)
          .with(number: 93, add: labels::ADDRESSED, remove: labels.displaced_by(labels::ADDRESSED))
      end
    end

    it "leaves one alone whose head is older than the rejection: nothing was fixed yet" do
      allow(github).to receive(:head_committed_at).and_return(rejected_at - 60)

      aggregate_failures do
        expect(upkeep.address).to be_empty
        expect(github).not_to have_received(:swap_label)
      end
    end

    it "says which pull request it could not read, and goes on with the rest" do
      allow(github).to receive(:open_pulls_labelled).and_return(93 => [], 94 => [])
      allow(github).to receive(:head_committed_at).with(number: 93).and_raise(OpenLanes::Error, "HTTP 502")
      allow(github).to receive(:head_committed_at).with(number: 94).and_return(rejected_at + 1)

      expect(upkeep.address).to eq(["PR #93 not checked for fixes: HTTP 502",
                                    "PR #94 review-addressed: committed 2026-10-19T10:09:12Z, after the rejection at 2026-10-19T10:09:11Z"])
    end
  end

  describe "#sweep" do
    it "labels a waiting pull request that no longer merges clean, comments once, and hands it back" do
      allow(github).to receive(:pull_request).and_return(live.merge(merge_state: "DIRTY"))
      sweep = upkeep.sweep(subjects)

      aggregate_failures do
        expect(sweep.conflicts).to eq([described_class::Conflict.new(ordinal: "033.00", number: 1, url:)])
        expect(github).to have_received(:swap_label).with(number: 1, add: labels::CONFLICTS, remove: ["conflicts-resolved"])
        expect(github).to have_received(:comment).once
      end
    end

    it "does not label or comment again on a pull request already labelled conflicts" do
      allow(github).to receive(:pull_request).and_return(live.merge(labels: %w[ready-to-merge conflicts], merge_state: "DIRTY"))

      aggregate_failures do
        expect(upkeep.sweep(subjects).conflicts.size).to eq(1)
        expect(github).not_to have_received(:swap_label)
        expect(github).not_to have_received(:comment)
      end
    end

    it "rebases one that is only behind main on GitHub, and notes when, for the CI grace" do
      allow(github).to receive(:pull_request).and_return(live.merge(merge_state: "BEHIND"))
      OpenLanes::Plans::PlanState.for(plan.feature.path).assess!({ 1 => "auto" })

      aggregate_failures do
        expect(upkeep.sweep(subjects).notes).to eq(["PR #1 was behind main; rebased on GitHub"])
        expect(github).to have_received(:update_branch).with(number: 1)
        expect(OpenLanes::Plans::PlanState.for(plan.feature.path).merge_risk.to_h.dig("rebased", "1")).to eq(now.iso8601)
      end
    end

    it "relabels conflicts-resolved once a conflicted pull request merges clean again" do
      allow(github).to receive(:pull_request).and_return(live.merge(labels: %w[merge-manually conflicts]))

      aggregate_failures do
        expect(upkeep.sweep(subjects).notes).to eq(["PR #1 merges clean onto main again: conflicts-resolved"])
        expect(github).to have_received(:swap_label).with(number: 1, add: labels::CONFLICTS_RESOLVED, remove: ["conflicts"])
      end
    end

    it "leaves pull requests still in review to their next round (U2)" do
      allow(github).to receive(:pull_request).and_return(live.merge(labels: %w[review-in-progress], merge_state: "DIRTY"))

      aggregate_failures do
        expect(upkeep.sweep(subjects).conflicts).to be_empty
        expect(github).not_to have_received(:swap_label)
      end
    end

    it "asks again only once main moves, or while GitHub has not decided" do
      allow(github).to receive(:pull_request).and_return(live.merge(merge_state: "UNKNOWN"), live, live)
      3.times { upkeep.sweep(subjects) }
      allow(github).to receive(:branch_head).and_return("main-2")
      upkeep.sweep(subjects)

      expect(github).to have_received(:pull_request).exactly(3).times
    end

    it "asks a plan an agent is working in later, rather than not at all" do
      upkeep.sweep(subjects, busy: ["033.00"])
      upkeep.sweep(subjects)

      expect(github).to have_received(:pull_request).once
    end

    it "says which pull request it could not ask, and keeps going" do
      allow(github).to receive(:pull_request).and_raise(OpenLanes::Error, "HTTP 502")

      expect(upkeep.sweep(subjects).notes).to eq(["033.00: #{url} not checked against main: HTTP 502"])
    end
  end

  describe "#attempt?" do
    it "lets a conflict be worked on once per head of main" do
      upkeep.sweep(subjects)
      conflict = described_class::Conflict.new(ordinal: "033.00", number: 1, url:)
      first = upkeep.attempt?(conflict)
      second = upkeep.attempt?(conflict)
      allow(github).to receive(:branch_head).and_return("main-2")
      upkeep.sweep(subjects)

      expect([first, second, upkeep.attempt?(conflict)]).to eq([true, false, true])
    end
  end
end
