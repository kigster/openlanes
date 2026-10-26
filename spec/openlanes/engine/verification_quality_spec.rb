# frozen_string_literal: true

# Which review verdicts go on to 🧪 at each `desired_codebase_quality` (R4).
RSpec.describe OpenLanes::Engine::Verification do
  describe ".from_review?" do
    it "lets review-approved through at every quality, and while unset" do
      aggregate_failures do
        [nil, :high, :standard, :mvp].each { expect(described_class.from_review?(%w[review-approved], quality: it)).to be(true) }
      end
    end

    it "lets review-ok-not-perfect through under mvp only" do
      aggregate_failures do
        expect(described_class.from_review?(%w[review-ok-not-perfect], quality: :mvp)).to be(true)
        expect(described_class.from_review?(%w[review-ok-not-perfect], quality: :high)).to be(false)
        expect(described_class.from_review?(%w[review-ok-not-perfect], quality: :standard)).to be(false)
        expect(described_class.from_review?(%w[review-ok-not-perfect])).to be(false)
      end
    end

    it "lets nothing else through, even under mvp" do
      expect(described_class.from_review?(%w[review-rejected], quality: :mvp)).to be(false)
    end
  end

  # Plan 035: under mvp an approved pull request skips verifier.
  describe ".skips_verification?" do
    it "is true for review-approved under mvp only" do
      aggregate_failures do
        expect(described_class.skips_verification?(%w[review-approved], quality: :mvp)).to be(true)
        [nil, :high, :standard].each { expect(described_class.skips_verification?(%w[review-approved], quality: it)).to be(false) }
        expect(described_class.skips_verification?(%w[review-ok-not-perfect], quality: :mvp)).to be(false)
      end
    end
  end

  describe ".ok_not_perfect?" do
    it "is true for the verdict the quality decides, and not when review-approved sits beside it" do
      aggregate_failures do
        expect(described_class.ok_not_perfect?(%w[review-ok-not-perfect])).to be(true)
        expect(described_class.ok_not_perfect?(%w[review-ok-not-perfect review-approved])).to be(false)
        expect(described_class.ok_not_perfect?(%w[review-rejected])).to be(false)
      end
    end
  end

  # Plan 035, the table in spec.md: mvp goes on, standard to 🟡, high to 🔴.
  # `max_rejections` is 2 for both high and standard; depth and models are
  # a later plan. This is the engine difference this one ships.
  describe "the three qualities at the 👀 → 🧪 hand-off" do
    it "takes a different path at each level for review-ok-not-perfect" do
      aggregate_failures do
        expect(described_class.from_review?(%w[review-ok-not-perfect], quality: :mvp)).to be(true)
        expect(described_class.from_review?(%w[review-ok-not-perfect], quality: :standard)).to be(false)
        expect(described_class.from_review?(%w[review-ok-not-perfect], quality: :high)).to be(false)
        expect(OpenLanes::Engine::Verification::Outcome::SEND_BACK).to eq(high: :rejected, standard: :building)
        expect(OpenLanes::Engine::Verification::Outcome::SEND_BACK).not_to have_key(:mvp)
      end
    end
  end
end
