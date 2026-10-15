# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::PrWatch, :tree do
  subject(:watch) { described_class.new(github:, clock: -> { now }) }

  let(:now) { 100.0 }
  let(:github) { instance_double(OpenLanes::Vcs::GitHub, pulls: rows, review_comments: comments) }
  let(:comments) { [{ author: "octo", body: "Fix the nil", url: "u1" }] }
  let(:rows) do
    [
      { number: 11, open: true, state: "Open 🟡", labels: %w[review-rejected] },
      { number: 12, open: true, state: "Open 🟡", labels: %w[ready-for-review] },
      { number: 13, open: false, state: "Merged 🟣", labels: [] },
      { number: 14, open: false, state: "Closed 🔴", labels: [] }
    ]
  end

  let(:subjects) do
    plans do |t|
      t.plan "001.00", :in_review, "rejected", prs: [t.open(11, "a")]
      t.plan "002.00", :in_review, "waiting", prs: [t.open(12, "b")]
      t.plan "003.00", :in_review, "merged", prs: [t.open(13, "c")]
      t.plan "004.00", :in_review, "closed", prs: [t.open(14, "d")]
      t.plan "005.00", :approved, "done", prs: [t.merged(15, "e")]
    end
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects
  end

  def kinds = watch.poll(subjects).to_h { |o| [o.pr, o.kind] }

  it "is not due before the interval has passed, and is once it has" do
    times = [100.0, 114.9, 115.0]
    paced = described_class.new(github:, clock: -> { times.first })

    aggregate_failures do
      expect(paced.due?).to be(false)
      times.shift
      expect(paced.due?).to be(false)
      times.shift
      expect(paced.due?).to be(true)
    end
  end

  it "makes one pulls call per poll, whatever the number of plans" do
    watch.poll(subjects)

    expect(github).to have_received(:pulls).once.with(state: "all")
  end

  it "names each open pull request's outcome" do
    expect(kinds).to eq(11 => :rejected, 12 => :waiting, 13 => :merged, 14 => :closed)
  end

  it "carries the comments of a rejected pull request, and asks for no others" do
    rejected = watch.poll(subjects).find { |o| o.kind == :rejected }

    aggregate_failures do
      expect(rejected).to have_attributes(plan: "001.00", comments:)
      expect(github).to have_received(:review_comments).once.with(number: 11)
    end
  end

  it "asks for no single pull request when the list has every watched one" do
    allow(github).to receive(:pull_request)
    watch.poll(subjects)

    expect(github).not_to have_received(:pull_request)
  end

  # `gh pr list` stops at its limit, newest first: an older pull request still
  # open must not drop out of the watch.
  context "when the list leaves out a watched pull request" do
    let(:rows) { [{ number: 12, open: true, state: "Open 🟡", labels: [] }] }

    let(:older) do
      { "11" => { number: 11, open: true, state: "Open 🟡", labels: %w[review-rejected] },
        "13" => { number: 13, open: false, state: "Merged 🟣", labels: [] } }
    end

    before do
      older.each { |ref, row| allow(github).to receive(:pull_request).with(ref).and_return(row) }
      allow(github).to receive(:pull_request).with("14").and_raise(OpenLanes::Error, "could not read pull request 14: offline")
    end

    it "asks for it by number, and skips only one it cannot read" do
      expect(kinds).to eq(11 => :rejected, 12 => :waiting, 13 => :merged)
    end
  end

  it "asks GitHub nothing when no plan has an open pull request" do
    plans { |t| t.plan "009.00", :approved, "only", prs: [t.merged(1, "x")] }

    expect(watch.poll(OpenLanes::Plans::Tree.new(dir: plans_root).subjects)).to eq([])
    expect(github).not_to have_received(:pulls)
  end
end
