# frozen_string_literal: true

RSpec.describe OpenLanes::Vcs::PullSnapshot do
  subject(:snapshot) { described_class.parse(pages, taken_at:) }

  let(:fixtures) { File.expand_path("../../fixtures/github", __dir__) }
  let(:pages) { %w[page1 page2].map { JSON.parse(File.read(File.join(fixtures, "pull_snapshot_#{it}.json"))) } }
  let(:taken_at) { Time.utc(2026, 11, 12, 20, 0) }

  it "reads every open pull request across both pages" do
    expect([snapshot.numbers, snapshot.taken_at]).to eq([[201, 202, 203, 204], taken_at])
  end

  it "builds each row in the shape GitHub#pull_request returns, plus files" do
    expect(snapshot[201].except(:checks, :complete)).to eq(
      number:       201,
      title:        "[061.00] Speed up openlanes",
      url:          "https://github.com/example/repo/pull/201",
      branch:       "tester/061.00-speed-up",
      files:        ["lib/openlanes/vcs/warmup.rb"],
      state:        "Open 🟡",
      open:         true,
      labels:       ["openlanes:review"],
      head:         "abc123",
      body:         "Speeds things up",
      merge_state:  "CLEAN",
      base:         "main",
      merge_commit: ""
    )
    expect(snapshot[202][:state]).to eq("WIP 🟡")
  end

  it "maps check runs and status contexts onto gh pr checks buckets" do
    expect(snapshot.checks(201)).to eq([
                                         { name: "rspec", bucket: "pass" },
                                         { name: "lint", bucket: "skipping" },
                                         { name: "ci/circleci: test", bucket: "pending" }
                                       ])
    expect(snapshot.checks(202)).to eq([{ name: "rspec", bucket: "pending" }])
    expect(snapshot.checks(203).map { it[:bucket] }).to eq(%w[fail fail pass])
  end

  it "feeds CiGate the same verdicts the per-PR reads did" do
    expect([201, 203].map { OpenLanes::Vcs::CiGate.verdict(snapshot.checks(it)) }).to eq(%i[pending red])
  end

  it "answers empty for a pull request with no CI, or one that is not open" do
    expect([snapshot.checks(204), snapshot.checks(999), snapshot.labels(999), snapshot[999]]).to eq([[], [], [], nil])
  end

  it "reads labels by number" do
    expect(snapshot.labels(203)).to eq(%w[openlanes:rejected bug])
  end

  it "names the next page's cursor, and none on the last" do
    expect(pages.map { described_class.next_cursor(it) }).to eq(["Y3Vyc29yOjE=", nil])
  end

  # A gate decides from these lists: a failing 101st check must not read green.
  describe "a pull request with more checks or labels than one page holds" do
    def node(**more) = { "number" => 9, "title" => "t", "url" => "https://github.com/o/r/pull/9", "state" => "OPEN" }.merge(more)

    let(:rollup) do
      { "nodes" => [{ "commit" => { "statusCheckRollup" => { "contexts" => { "pageInfo" => { "hasNextPage" => true }, "nodes" => [] } } } }] }
    end
    let(:pages) do
      [{ "data" => { "repository" => { "pullRequests" => { "nodes" => [
        node("commits" => rollup),
        node("number" => 10, "labels" => { "pageInfo" => { "hasNextPage" => true }, "nodes" => [] }),
        node("number" => 11, "labels" => { "pageInfo" => { "hasNextPage" => false }, "nodes" => [] })
      ] } } } }]
    end

    it "is held, but not offered as complete, so a reader asks GitHub for it" do
      expect([snapshot.numbers, [9, 10, 11].map { snapshot.complete(it)&.fetch(:number) }]).to eq([[9, 10, 11], [nil, nil, 11]])
    end
  end
end
