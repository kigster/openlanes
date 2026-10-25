# frozen_string_literal: true

# Decisions U2 and U4: a real `.plans` tree and a double for the GitHub seam,
# so what is under test is which pull requests are asked about, and what
# reaches GitHub for each answer.
RSpec.describe OpenLanes::Engine::Upkeep::Sweep, :tree do
  subject(:sweep) { described_class.new(github:, owed:, actions: OpenLanes::Engine::Upkeep::Actions.new(github:, clock: -> { now })) }

  let(:github) { instance_double(OpenLanes::Vcs::GitHub) }
  let(:owed) { OpenLanes::Engine::Upkeep::Owed.new }
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

  it "labels a waiting pull request that no longer merges clean, comments once, and hands it back" do
    allow(github).to receive(:pull_request).and_return(live.merge(merge_state: "DIRTY"))
    result = sweep.call(subjects)

    aggregate_failures do
      expect(result.conflicts).to eq([OpenLanes::Engine::Upkeep::Conflict.new(ordinal: "033.00", number: 1, url:)])
      expect(github).to have_received(:swap_label).with(number: 1, add: labels::CONFLICTS, remove: ["conflicts-resolved"])
      expect(github).to have_received(:comment).once
    end
  end

  it "does not label or comment again on a pull request already labelled conflicts" do
    allow(github).to receive(:pull_request).and_return(live.merge(labels: %w[ready-to-merge conflicts], merge_state: "DIRTY"))

    aggregate_failures do
      expect(sweep.call(subjects).conflicts.size).to eq(1)
      expect(github).not_to have_received(:swap_label)
      expect(github).not_to have_received(:comment)
    end
  end

  it "rebases one that is only behind main on GitHub, and notes when, for the CI grace" do
    allow(github).to receive(:pull_request).and_return(live.merge(merge_state: "BEHIND"))
    OpenLanes::Plans::PlanState.for(plan.feature.path).assess!({ 1 => "auto" })

    aggregate_failures do
      expect(sweep.call(subjects).notes).to eq(["PR #1 was behind main; rebased on GitHub"])
      expect(github).to have_received(:update_branch).with(number: 1)
      expect(OpenLanes::Plans::PlanState.for(plan.feature.path).merge_risk.to_h.dig("rebased", "1")).to eq(now.iso8601)
    end
  end

  it "relabels conflicts-resolved once a conflicted pull request merges clean again" do
    allow(github).to receive(:pull_request).and_return(live.merge(labels: %w[merge-manually conflicts]))

    aggregate_failures do
      expect(sweep.call(subjects).notes).to eq(["PR #1 merges clean onto main again: conflicts-resolved"])
      expect(github).to have_received(:swap_label).with(number: 1, add: labels::CONFLICTS_RESOLVED, remove: ["conflicts"])
    end
  end

  it "leaves pull requests still in review to their next round (U2)" do
    allow(github).to receive(:pull_request).and_return(live.merge(labels: %w[review-in-progress], merge_state: "DIRTY"))

    aggregate_failures do
      expect(sweep.call(subjects).conflicts).to be_empty
      expect(github).not_to have_received(:swap_label)
    end
  end

  it "asks again only once main moves, or while GitHub has not decided" do
    allow(github).to receive(:pull_request).and_return(live.merge(merge_state: "UNKNOWN"), live, live)
    3.times { sweep.call(subjects) }
    allow(github).to receive(:branch_head).and_return("main-2")
    sweep.call(subjects)

    expect(github).to have_received(:pull_request).exactly(3).times
  end

  it "asks a plan an agent is working in later, rather than not at all" do
    sweep.call(subjects, busy: ["033.00"])
    sweep.call(subjects)

    expect(github).to have_received(:pull_request).once
  end

  it "says which pull request it could not ask, and keeps going" do
    allow(github).to receive(:pull_request).and_raise(OpenLanes::Error, "HTTP 502")

    expect(sweep.call(subjects).notes).to eq(["033.00: #{url} not checked against main: HTTP 502"])
  end
end
