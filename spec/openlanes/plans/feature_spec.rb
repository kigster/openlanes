# frozen_string_literal: true

require "spec_helper"

# The `## B<n>` / `## A<n>` notation is the only part of `blocked.md` a program
# can read. A folder whose questions are written any other way is invisible to
# the whole tool, which is what these examples pin down.
RSpec.describe OpenLanes::Plans::Subject, :tree do
  let!(:tree) do
    plans do |t|
      t.plan "001.00",
        :blocked,
        "asks",
        files: {
          "spec.md" => "x", "plan.md" => "y",
                "blocked.md" => <<~MD
                  ## B1. Which rate source?
                  ## B2. Who owns the perimeter?
                  ## A1
                  Decided 2026-08-21 by the CTO: the vendor feed.
                MD
        }
      t.plan "002.00",
        :building,
        "unreadable",
        files: {
          "spec.md" => "x", "plan.md" => "y",
                "blocked.md" => "## 1. Item health\n## Q1 — suppress or annotate?\n"
        }
      t.plan "003.00", :building, "clean", files: { "spec.md" => "x", "plan.md" => "y" }
    end
  end

  let(:plans_tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }

  def subject_for(ordinal) = plans_tree.find(ordinal)

  describe "#open_blocks and #block_answers" do
    it "counts the questions and the answers separately" do
      aggregate_failures do
        expect(subject_for("001.00").open_blocks).to eq([1, 2])
        expect(subject_for("001.00").block_answers).to eq([1])
      end
    end

    # `## A1` sitting in the same file must never read as a fourth question,
    # or a folder would stay blocked by its own answers.
    it "never reads an answer as a question" do
      expect(subject_for("001.00").open_blocks).not_to include(0)
    end
  end

  describe "#unreadable_block?" do
    # The bug this whole change exists for: 31k of real questions numbered
    # `## 1.` and `## Q1`, reported by the tool as nothing at all.
    it "is true for a blocked.md whose questions use some other notation" do
      expect(subject_for("002.00")).to be_unreadable_block
    end

    it "is false when the questions are numbered the way the tool reads them" do
      expect(subject_for("001.00")).not_to be_unreadable_block
    end

    it "is false when there is no blocked.md at all, which is a different thing" do
      expect(subject_for("003.00")).not_to be_unreadable_block
    end
  end
end

# The folder name is the state, so its spelling is an interface: canonical is
# `NNN.MM-<emoji> → <slug>` — the spaced arrow keeps the two-cell emoji from
# visually swallowing the separator — and the double-dash and single-dash
# spellings every folder wore before the rule still decode, so `resync dirs`
# can migrate them instead of misreading them.
RSpec.describe OpenLanes::Plans::Feature do
  def parsed(dirname) = described_class.parse("/plans/#{dirname}")

  it "mints the canonical arrow name" do
    status = OpenLanes::Plans::STATUS_BY_KEY.fetch(:planned)

    expect(OpenLanes::Plans.plan_dirname("003.00", status, "tax-rule-dsl")).to eq("003.00-⭐️ → tax-rule-dsl")
  end

  it "decodes a canonical name" do
    feature = parsed("003.00-⭐️ → tax-rule-dsl")

    expect(feature.slug).to eq("tax-rule-dsl")
    expect(feature.status.key).to eq(:planned)
    expect(feature).to be_canonical
  end

  it "decodes an unspaced arrow, as non-canonical" do
    feature = parsed("003.00-⭐️→tax-rule-dsl")

    expect(feature.slug).to eq("tax-rule-dsl")
    expect(feature.status.key).to eq(:planned)
    expect(feature).not_to be_canonical
  end

  it "still decodes the double-dash spelling of the `--` era, as non-canonical" do
    feature = parsed("003.00-⭐️--tax-rule-dsl")

    expect(feature.slug).to eq("tax-rule-dsl")
    expect(feature.status.key).to eq(:planned)
    expect(feature).not_to be_canonical
    expect(feature.dirname_as(feature.status)).to eq("003.00-⭐️ → tax-rule-dsl")
  end

  it "still decodes the older single-dash spelling, as non-canonical" do
    feature = parsed("003.00-⭐️-tax-rule-dsl")

    expect(feature.slug).to eq("tax-rule-dsl")
    expect(feature.status.key).to eq(:planned)
    expect(feature).not_to be_canonical
    expect(feature.dirname_as(feature.status)).to eq("003.00-⭐️ → tax-rule-dsl")
  end
end
