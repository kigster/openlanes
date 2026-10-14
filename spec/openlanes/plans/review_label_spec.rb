# frozen_string_literal: true

# M3 in docs/decisions/decisions-on-merge-modes-and-verification.md is the
# source; these examples hold the code to it, colour for colour.
RSpec.describe OpenLanes::Plans::ReviewLabel do
  it "carries the six M3 labels with their colours, in order" do
    expect(described_class::ALL.to_h { |l| [l.name, l.colour] }).to eq(
      "ready-for-review"   => "c2e0c6",
      "review-in-progress" => "fff3b0",
      "review-passed"      => "1d76db",
      "ready-to-merge"     => "2ea043",
      "review-rejected"    => "b60205",
      "ok-to-merge"        => "1a7f37"
    )
  end

  it "counts exactly three verdicts as passing" do
    expect(described_class.passing.map(&:name)).to eq(%w[review-passed ready-to-merge ok-to-merge])
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
