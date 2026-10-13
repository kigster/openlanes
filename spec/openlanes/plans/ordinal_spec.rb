# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::Ordinal do
  describe ".parse" do
    it "accepts the canonical form, pads legacy and bare numbers, and rejects everything else" do
      aggregate_failures do
        expect(described_class.parse("018.01").to_s).to eq("018.01")
        expect(described_class.parse("018").to_s).to eq("018.00")
        expect(described_class.parse("3").to_s).to eq("003.00")
        expect(described_class.parse("0").to_s).to eq("000.00")
        expect(described_class.parse(" 007 ").to_s).to eq("007.00")
        expect(described_class.parse("draft")).to be_nil
        expect(described_class.parse("")).to be_nil
        expect(described_class.parse(nil)).to be_nil
      end
    end
  end

  describe ".from_dirname" do
    it "lifts the number off a folder name and ignores folders without one" do
      aggregate_failures do
        expect(described_class.from_dirname("018.01-✅--verify-returns").to_s).to eq("018.01")
        expect(described_class.from_dirname("002-⚪️--legacy-shape").to_s).to eq("002.00")
        expect(described_class.from_dirname("notes")).to be_nil
      end
    end
  end

  describe "retroactivity" do
    subject { described_class.parse(number) }

    context "with an ordinary plan" do
      let(:number) { "018.00" }

      it { is_expected.not_to be_retroactive }
    end

    context "with a plan documented after the fact" do
      let(:number) { "018.01" }

      it { is_expected.to be_retroactive }
    end
  end

  describe "ordering" do
    let(:shuffled) { %w[019.00 018.10 003.00 018.01 000.01 018.00].map { |n| described_class.parse(n) } }

    it "sorts .01 before .10, which is the entire reason the decimal is two digits" do
      expect(shuffled.sort.map(&:to_s)).to eq(%w[000.01 003.00 018.00 018.01 018.10 019.00])
    end

    it "puts 000.MM first, where pre-discipline work belongs" do
      expect(shuffled.min.to_s).to eq("000.01")
    end
  end

  describe ".next_major" do
    it "starts an empty tree at 000.00" do
      expect(described_class.next_major([]).to_s).to eq("000.00")
    end

    it "takes the highest whole number plus one, and always lands on .00" do
      aggregate_failures do
        expect(described_class.next_major([described_class.parse("000.00")]).to_s).to eq("001.00")
        expect(described_class.next_major(%w[002.00 002.01].map { |n| described_class.parse(n) }).to_s).to eq("003.00")
      end
    end

    it "counts from the highest major, not the number of plans" do
      existing = %w[000.00 007.00 007.03].map { |n| described_class.parse(n) }

      expect(described_class.next_major(existing).to_s).to eq("008.00")
    end
  end

  describe ".next_minor" do
    let(:existing) { %w[002.00 002.01 003.00].map { |n| described_class.parse(n) } }

    it "takes the next free slot in the gap after the anchor" do
      expect(described_class.next_minor(existing, major: 2).to_s).to eq("002.02")
    end

    it "does not touch a neighbouring plan's slots" do
      expect(described_class.next_minor(existing, major: 3).to_s).to eq("003.01")
    end

    context "when all 99 slots are taken" do
      let(:full) { (0..99).map { |m| described_class.new(major: 2, minor: m) } }

      it "refuses rather than overflowing into the next plan" do
        expect { described_class.next_minor(full, major: 2) }.to raise_error(OpenLanes::Error, /all 99 retroactive slots/)
      end
    end
  end

  describe "#to_prefix" do
    subject { described_class.parse("018.01").to_prefix }

    it { is_expected.to eq("[018.01]") }
  end
end
