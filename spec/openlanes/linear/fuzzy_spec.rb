# frozen_string_literal: true

# The threshold is calibrated, not chosen: the comment in fuzzy.rb names the
# exact pairs it was set between, so the examples here pin those pairs. If a
# gem upgrade shifts the scores, these fail by name instead of a pull request
# silently filing under the wrong folder.
RSpec.describe OpenLanes::Linear::Fuzzy do
  describe ".similarity" do
    it "grades on a scale rather than a yes or no" do
      expect(described_class.similarity("rounding", "round")).to be_between(0.9, 1.0)
    end

    it "compares case-insensitively, since folder slugs are lowercase and titles are not" do
      expect(described_class.similarity("Ledger", "ledger")).to eq(1.0)
    end
  end

  describe ".akin?" do
    it "treats a word and its inflection as the same word" do
      aggregate_failures do
        expect(described_class.akin?("rounding", "round")).to be(true)
        expect(described_class.akin?("vintages", "vintage")).to be(true)
      end
    end

    # These pairs sit just under the threshold, and they are why it is 0.93:
    # each is a genuinely different word that a lower bar would conflate.
    it "does not conflate different words that merely share a prefix" do
      aggregate_failures do
        expect(described_class.akin?("plaid", "plain")).to be(false)
        expect(described_class.akin?("state", "statement")).to be(false)
      end
    end
  end

  describe ".coverage" do
    it "asks how much of the folder's name the title said, not the reverse" do
      folder = %w[ledger carryforward]
      long_title = %w[completely rework ledger carryforward handling with tests]

      expect(described_class.coverage(folder, long_title)).to eq(1.0)
    end

    it "counts an inflected word as said" do
      expect(described_class.coverage(%w[vintage], %w[vintages])).to eq(1.0)
    end

    it "reports the fraction when only part of the name was said" do
      expect(described_class.coverage(%w[ledger carryforward vintages], %w[ledger work])).to be_within(0.001).of(1.0 / 3)
    end

    # An empty folder name covered "entirely" would match every title.
    it "covers nothing when there is nothing to cover" do
      expect(described_class.coverage([], %w[anything])).to eq(0.0)
    end
  end
end
