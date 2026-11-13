# frozen_string_literal: true

RSpec.describe OpenLanes::Vcs::SnapshotReads do
  subject(:reads) { described_class.new(github, snapshot:) }

  let(:github) { instance_double(OpenLanes::Vcs::GitHub, labels: %w[live], checks: [{ name: "live", bucket: "pass" }], swap_label: nil, merge: nil) }
  let(:row) { { number: 7, url: "https://github.com/o/r/pull/7", labels: %w[review-approved], checks: [{ name: "ci", bucket: "pending" }] } }
  let(:snapshot) do
    taken = OpenLanes::Vcs::PullSnapshot.new(pulls: [row], taken_at: Time.at(0))
    Struct.new(:taken, :refreshed) {
      def call = taken
      def refresh! = self.refreshed = true
    }.new(taken, false)
  end

  it "answers labels and checks of a pull request the snapshot holds, without asking GitHub" do
    expect([reads.labels(number: 7, repo: "o/r"), reads.checks(number: 7)]).to eq([%w[review-approved], row[:checks]])
    expect(github).not_to have_received(:labels)
    expect(github).not_to have_received(:checks)
  end

  it "asks GitHub about one the snapshot does not hold, or in another repository" do
    expect([reads.labels(number: 8), reads.checks(number: 7, repo: "x/y")]).to eq([%w[live], [{ name: "live", bucket: "pass" }]])
  end

  context "when the snapshot's row was truncated" do
    let(:row) { { number: 7, url: "https://github.com/o/r/pull/7", labels: %w[review-approved], checks: [], complete: false } }

    it "reads its labels and checks live, so CiGate never decides from a partial list" do
      expect([reads.labels(number: 7), reads.checks(number: 7)]).to eq([%w[live], [{ name: "live", bucket: "pass" }]])
    end
  end

  describe "#pull_request" do
    let(:github) { instance_double(OpenLanes::Vcs::GitHub, pull_request: { number: 9, open: false, merge_commit: "abc" }) }
    let(:row) do
      { number: 7, url: "https://github.com/o/r/pull/7", labels: %w[x], files: %w[a.rb], checks: [], head: "def", merge_state: "CLEAN", open: true }
    end

    it "answers one the snapshot holds, by URL or number, in GitHub#pull_request's shape" do
      expect(reads.pull_request("https://github.com/o/r/pull/7")).to include(head: "def", merge_state: "CLEAN", open: true)
      expect(reads.pull_request("7")).not_to include(:files, :checks)
      expect(github).not_to have_received(:pull_request)
    end

    it "reads one that left the snapshot, or is in another repository, or is no pull request, live" do
      %w[https://github.com/o/r/pull/9 https://github.com/x/y/pull/7 main].each { reads.pull_request(it) }
      expect(github).to have_received(:pull_request).exactly(3).times
    end
  end

  it "drops the snapshot on a write, and passes the write on" do
    reads.swap_label(number: 7, add: :x)
    expect(snapshot.refreshed).to be(true)
    expect(github).to have_received(:swap_label).with(number: 7, add: :x)
  end

  it "passes every other call straight through" do
    reads.merge(number: 7, head: "abc")
    expect(github).to have_received(:merge).with(number: 7, head: "abc")
  end
end
