# frozen_string_literal: true

# R3: the engine makes every review label exist on the repository, in R3's
# colours, when it starts on a project.
RSpec.describe OpenLanes::Vcs::LabelSync do
  subject(:sync) { described_class.new(github:) }

  let(:github) { instance_double(OpenLanes::Vcs::GitHub, ensure_label: nil, recolour_label: nil) }
  let(:labels) { OpenLanes::Plans::ReviewLabel }
  let(:in_r3_colours) { labels::ALL.to_h { [it.name, it.colour.downcase] } }

  before { allow(github).to receive(:label_colours).and_return(have) }

  context "with a repository labelled under M3" do
    let(:have) { { "ready-for-review" => "c2e0c6", "review-rejected" => "b60205", "ok-to-merge" => "1a7f37", "bug" => "d73a4a" } }

    it "creates the missing labels and recolours the mismatched ones" do
      changes = sync.call(repo: "o/r")

      aggregate_failures do
        expect(changes.to_h { [it.label.name, it.action] }).to eq(
          "ready-for-review"      => :keep,
          "review-in-progress"    => :create,
          "review-rejected"       => :recolour,
          "review-vulnerability"  => :create,
          "review-ok-not-perfect" => :create,
          "review-approved"       => :create,
          "ready-to-merge"        => :create
        )
        expect(github).to have_received(:recolour_label).with(labels::REJECTED, repo: "o/r")
        expect(github).to have_received(:ensure_label).exactly(5).times
      end
    end

    it "says what it changed, one line each" do
      lines = sync.call.select(&:write?).map(&:to_s)

      expect(lines).to include("recolour review-rejected #b60205 → #F90000", "create ready-to-merge (#5319e7)")
    end

    it "writes nothing under a dry run, and answers the same changes" do
      changes = sync.call(dry_run: true)

      aggregate_failures do
        expect(changes.count(&:write?)).to eq(6)
        expect(github).not_to have_received(:ensure_label)
        expect(github).not_to have_received(:recolour_label)
      end
    end
  end

  context "with every label already right" do
    let(:have) { in_r3_colours }

    it "keeps them all and writes nothing, so a second run is free" do
      aggregate_failures do
        expect(sync.call.map(&:action).uniq).to eq([:keep])
        expect(sync.call.first.to_s).to eq("keep ready-for-review")
        expect(github).not_to have_received(:ensure_label)
        expect(github).not_to have_received(:recolour_label)
      end
    end
  end

  context "with GitHub answering a colour in a different case" do
    let(:have) { in_r3_colours.merge("review-in-progress" => "ffbe20") }

    it "does not count it as a mismatch" do
      expect(sync.call.find { it.label.name == "review-in-progress" }.action).to eq(:keep)
    end
  end
end
