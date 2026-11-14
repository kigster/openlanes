# frozen_string_literal: true

# R3 in docs/decisions/decisions-on-three-reviewers-and-auto-merge.md is the
# source, with V2's rename in decisions-on-agent-names-models-and-reviewers.md;
# these examples hold the code to them, colour for colour.
RSpec.describe OpenLanes::Plans::ReviewLabel do
  it "carries the R3 labels, the harness's review-addressed (U1) and deploy-assessor's two verdicts (P2), with their colours, in order" do
    expect(described_class::ALL.to_h { |l| [l.name, l.colour] }).to eq(
      "ready-for-review"   => "c2e0c6",
      "review-in-progress" => "FFBE20",
      "review-rejected"    => "F90000",
      "review-addressed"   => "A2FF02",
      "review-passed"      => "E8E890",
      "review-approved"    => "109a10",
      "ready-to-merge"     => "5319e7",
      "auto-merged"        => "953384",
      "merge-manually"     => "0e8a16"
    )
  end

  it "counts the passing verdicts, and everything after them, as passing" do
    expect(described_class.passing.map(&:name)).to eq(%w[review-passed review-approved ready-to-merge auto-merged merge-manually])
  end

  it "keeps no label that was retired or renamed" do
    expect(described_class.names & %w[review-ok-not-perfect ok-to-merge]).to be_empty
  end

  it "renames R3's review-ok-not-perfect to V2's review-passed, and review-vulnerability to opsec-rejected" do
    expect(described_class::RENAMED).to eq("review-ok-not-perfect" => described_class::PASSED,
      "review-vulnerability" => described_class::OPSEC_REJECTED)
  end

  it "fits every meaning in GitHub's 100-character label description" do
    expect([*described_class::SYNCED, described_class::MIGRATED].map { it.meaning.length }).to all(be <= 100)
  end

  it "names three risks and three security verdicts, beside the verdicts and never among them" do
    aggregate_failures do
      expect(described_class::RISK.map(&:name)).to eq(%w[risk-low risk-medium risk-high])
      expect(described_class::OPSEC.map(&:name)).to eq(%w[opsec-approved opsec-concerned-approved opsec-rejected])
      expect(described_class::ALL & described_class::FAMILIES.flatten).to be_empty
      expect(described_class::SYNCED).to include(*described_class::FAMILIES.flatten)
    end
  end

  it "merges on review-approved, risk-low and opsec-approved, and says which of them a pull request lacks" do
    aggregate_failures do
      expect(described_class::MERGEABLE.map(&:name)).to eq(%w[review-approved risk-low opsec-approved])
      expect(described_class.unmergeable(%w[review-approved risk-low opsec-approved ready-to-merge])).to be_empty
      expect(described_class.unmergeable(%w[review-passed risk-low opsec-concerned-approved])).to eq(%w[review-approved opsec-approved])
    end
  end

  it "finds a risk or a security verdict by name, and no verdict" do
    aggregate_failures do
      expect(described_class.beside("risk-low")).to eq(described_class::RISK_LOW)
      expect(described_class.beside(described_class::OPSEC_REJECTED)).to eq(described_class::OPSEC_REJECTED)
      expect(described_class.beside("review-approved")).to be_nil
    end
  end

  # LabelSync walks ALL; the migration's marker must be one it never touches.
  it "keeps the migration's marker out of the verdicts" do
    aggregate_failures do
      expect(described_class::ALL).not_to include(described_class::MIGRATED)
      expect(described_class.known).not_to include(described_class::MIGRATED.name)
    end
  end

  describe ".displaced_by" do
    it "takes every other label off for an ordinary verdict" do
      expect(described_class.displaced_by(described_class::APPROVED))
        .to eq(described_class.names - %w[review-approved] + described_class::RETIRED)
    end

    # Grok on #69: #62 carried a verdict R3 no longer named.
    it "takes the retired verdicts off too" do
      described_class::ALL.each do |label|
        expect(described_class.displaced_by(label)).to include("review-ok-not-perfect", "ok-to-merge", "review-vulnerability")
      end
    end

    it "leaves the reviewers' passing verdict beside the labels that follow it" do
      aggregate_failures do
        %w[review-in-progress ready-to-merge auto-merged merge-manually].each do |name|
          expect(described_class.displaced_by(described_class.fetch(name))).not_to include("review-approved", "review-passed")
        end
        expect(described_class.displaced_by(described_class::REJECTED)).to include("review-approved", "ready-for-review")
        expect(described_class.displaced_by(described_class::ADDRESSED)).to include("review-approved", "review-rejected")
      end
    end

    it "takes only its own family off for a risk or a security verdict" do
      aggregate_failures do
        expect(described_class.displaced_by(described_class::RISK_LOW)).to eq(%w[risk-medium risk-high])
        expect(described_class.displaced_by(described_class::OPSEC_REJECTED)).to eq(%w[opsec-approved opsec-concerned-approved])
      end
    end

    it "takes the last judgement's risk and security verdict off when a new one opens, and at no other time" do
      beside = described_class::FAMILIES.flatten.map(&:name)

      aggregate_failures do
        expect(described_class.displaced_by(described_class::INITIAL)).to include(*beside)
        expect(described_class.displaced_by(described_class::ADDRESSED)).to include(*beside)
        (described_class::ALL - described_class::FRESH).each do |label|
          expect(described_class.displaced_by(label) & beside).to be_empty
        end
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
