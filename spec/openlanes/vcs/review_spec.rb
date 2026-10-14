# frozen_string_literal: true

# A fake GitHub that keeps the label set, so "exactly one review label is left"
# is asserted on state rather than on which arguments happened to be passed.
class FakeReviewGitHub
  attr_reader :labels_on, :writes
  attr_accessor :buckets

  def initialize(labels: [], buckets: %w[pass])
    @labels_on = labels.dup
    @buckets = buckets
    @writes = []
  end

  def labels(**) = @labels_on.dup

  def checks(**) = buckets.map { |b| { name: "ci", bucket: b } }

  def swap_label(number:, add:, repo: nil, remove: [])
    @writes << [number, repo, add.name, remove]
    @labels_on = (@labels_on - remove.map(&:to_s)) | [add.name]
  end
end

RSpec.describe OpenLanes::Vcs::Review do
  subject(:review) { described_class.new(github:) }

  let(:github) { FakeReviewGitHub.new(labels: %w[ready-for-review bug]) }
  let(:review_labels) { -> { github.labels_on & OpenLanes::Plans::ReviewLabel.names } }

  it "replaces the review label at every transition, leaving exactly one" do
    %w[review-in-progress review-rejected review-in-progress ready-to-merge ok-to-merge].each do |label|
      review.call(pr: "12", label:)
      expect(review_labels.call).to eq([label])
    end
    expect(github.labels_on).to include("bug")
  end

  it "reports from, to and the CI verdict" do
    result = review.call(pr: "#12", label: "review-in-progress")

    expect(result).to have_attributes(pr: 12,
      from: %w[ready-for-review],
      to: "review-in-progress",
      ci: :green,
      refused?: false,
      reason: nil,
      dry_run?: false)
  end

  it "takes owner and repo from a pull request URL" do
    review.call(pr: "https://github.com/example/repo/pull/7", label: "review-in-progress")

    expect(github.writes.last.first(2)).to eq([7, "example/repo"])
  end

  context "when CI is red" do
    before { github.buckets = %w[pass fail] }

    OpenLanes::Plans::ReviewLabel.passing.each do |label|
      it "refuses #{label.name} and writes nothing" do
        result = review.call(pr: "12", label: label.name)

        aggregate_failures do
          expect(result).to have_attributes(refused?: true, reason: "CI is red", ci: :red)
          expect(github.writes).to be_empty
        end
      end
    end

    it "accepts review-rejected" do
      expect(review.call(pr: "12", label: "review-rejected")).not_to be_refused
      expect(review_labels.call).to eq(%w[review-rejected])
    end
  end

  it "makes a passing verdict wait while CI is pending" do
    github.buckets = %w[pending]

    expect(review.call(pr: "12", label: "ready-to-merge")).to have_attributes(refused?: true, reason: "CI pending")
  end

  it "treats no checks as green, with a warning" do
    github.buckets = []

    expect(review.call(pr: "12", label: "review-passed"))
      .to have_attributes(refused?: false, ci: :none, reason: described_class::NO_CHECKS)
  end

  it "writes nothing under a dry run" do
    result = review.call(pr: "12", label: "review-in-progress", dry_run: true)

    aggregate_failures do
      expect(result).to have_attributes(dry_run?: true, refused?: false)
      expect(github.writes).to be_empty
    end
  end

  it "rejects an unknown label before asking GitHub anything" do
    allow(github).to receive(:labels)
    expect { review.call(pr: "12", label: "lgtm") }.to raise_error(OpenLanes::Error, /one of: ready-for-review/)
    expect(github).not_to have_received(:labels)
  end

  it "is reachable through the Vcs facade" do
    expect(OpenLanes::Vcs.review(github:)).to be_a(described_class)
  end
end
