# frozen_string_literal: true

# R3 in docs/decisions/decisions-on-three-reviewers-and-auto-merge.md is the
# source; these examples hold the code to it, colour for colour.
RSpec.describe OpenLanes::Plans::ReviewLabel do
  it "carries the seven R3 labels with their colours, in order" do
    expect(described_class::ALL.to_h { |l| [l.name, l.colour] }).to eq(
      "ready-for-review"      => "c2e0c6",
      "review-in-progress"    => "FFBE20",
      "review-rejected"       => "F90000",
      "review-vulnerability"  => "FF0050",
      "review-ok-not-perfect" => "E8E890",
      "review-approved"       => "109a10",
      "ready-to-merge"        => "5319e7"
    )
  end

  it "counts exactly three labels as passing" do
    expect(described_class.passing.map(&:name)).to eq(%w[review-ok-not-perfect review-approved ready-to-merge])
  end

  it "keeps no M3 label that R3 retired or renamed" do
    expect(described_class.names & %w[review-passed ok-to-merge]).to be_empty
  end

  it "fits every meaning in GitHub's 100-character label description" do
    expect(described_class::ALL.map { it.meaning.length }).to all(be <= 100)
  end

  describe ".displaced_by" do
    it "takes every other label off for an ordinary verdict" do
      expect(described_class.displaced_by(described_class::APPROVED))
        .to eq(described_class.names - %w[review-approved] + described_class::RETIRED)
    end

    # Grok on #69: #62 carries M3's review-passed, which R3 no longer names.
    it "takes M3's retired verdicts off too" do
      described_class::ALL.each do |label|
        expect(described_class.displaced_by(label)).to include("review-passed", "ok-to-merge")
      end
    end

    it "leaves review-rejected beside review-vulnerability, and the other way round" do
      aggregate_failures do
        expect(described_class.displaced_by(described_class::VULNERABILITY)).not_to include("review-rejected")
        expect(described_class.displaced_by(described_class::REJECTED)).not_to include("review-vulnerability")
        expect(described_class.displaced_by(described_class::REJECTED)).to include("review-approved", "ready-for-review")
      end
    end
  end

  it "opens every pull request at ready-for-review" do
    expect(described_class::INITIAL.name).to eq("ready-for-review")
  end

  it "fetches by name" do
    expect(described_class.fetch("review-rejected")).to eq(described_class::REJECTED)
  end

  it "names the valid labels when asked for an unknown one" do
    expect { described_class.fetch("lgtm") }
      .to raise_error(OpenLanes::Error, /unknown review label "lgtm"; one of: ready-for-review, review-in-progress/)
  end

  it "interpolates as its name" do
    expect("#{described_class::INITIAL}").to eq("ready-for-review") # rubocop:disable Style/RedundantInterpolation
  end
end
