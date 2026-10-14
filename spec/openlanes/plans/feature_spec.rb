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
# `NNN.MM━━<emoji>━━❯<slug>`, dated `━━❯[YYYY-MM-DD]━━<slug>` once moved aside
# (decisions N1, N3). Every spelling a folder wore before still decodes, so
# `resync dirs` can migrate it instead of misreading it.
RSpec.describe OpenLanes::Plans::Feature do
  def parsed(dirname) = described_class.parse("/plans/#{dirname}")

  it "mints the canonical name" do
    status = OpenLanes::Plans::STATUS_BY_KEY.fetch(:planned)

    expect(OpenLanes::Plans.plan_dirname("003.00", status, "tax-rule-dsl")).to eq("003.00━━⭐━━❯tax-rule-dsl")
  end

  it "mints the dated name of a plan moved aside" do
    status = OpenLanes::Plans::STATUS_BY_KEY.fetch(:approved)

    expect(OpenLanes::Plans.plan_dirname("002.00", status, "dev-foundation", archived_on: Date.new(2026, 10, 13)))
      .to eq("002.00━━✅━━❯[2026-10-13]━━dev-foundation")
  end

  it "never puts a space in a name, in any state" do
    names = OpenLanes::Plans::STATUSES.map { OpenLanes::Plans.plan_dirname("001.00", it, "x") }

    expect(names.grep(/\s/)).to be_empty
  end

  it "round-trips every state, dated and not" do
    OpenLanes::Plans::STATUSES.each do |status|
      [nil, Date.new(2026, 1, 2)].each do |date|
        feature = parsed(OpenLanes::Plans.plan_dirname("004.01", status, "a-b", archived_on: date))

        expect([feature.status, feature.slug, feature.archived_on]).to eq([status, "a-b", date])
        expect(feature).to be_canonical
      end
    end
  end

  # Every spelling a folder has worn, with what it decodes to.
  {
    "003.00━━⭐━━❯tax-rule-dsl"                 => [:planned, "tax-rule-dsl", nil, true],
    "002.00━━✅━━❯[2026-10-13]━━dev-foundation" => [:approved, "dev-foundation", Date.new(2026, 10, 13), true],
    "003.00-⭐️ → tax-rule-dsl"                 => [:planned, "tax-rule-dsl", nil, false],
    "003.00-⭐️→tax-rule-dsl"                   => [:planned, "tax-rule-dsl", nil, false],
    "003.00-⭐️--tax-rule-dsl"                  => [:planned, "tax-rule-dsl", nil, false],
    "003.00-⭐️-tax-rule-dsl"                   => [:planned, "tax-rule-dsl", nil, false],
    "018-🅱️--pricing"                          => [:product_blocked, "pricing", nil, false],
    "018.00-🅱 → pricing"                       => [:product_blocked, "pricing", nil, false],
    "018.00━━🛑━━❯pricing"                      => [:product_blocked, "pricing", nil, true],
    "019.00-☢️ → later"                        => [:deferred, "later", nil, false],
    "019.00━━💤━━❯later"                        => [:deferred, "later", nil, true],
    "005.01-🕰️-k1"                             => [:retroactive, "k1", nil, false],
    "005.01━━⏪━━❯k1"                           => [:retroactive, "k1", nil, true],
    "006.00-⭕️ → stuck"                        => [:blocked, "stuck", nil, false],
    "007.00-⚪️ → fresh"                        => [:new, "fresh", nil, false]
  }.each do |dirname, (key, slug, date, canonical)|
    it "decodes #{dirname}" do
      feature = parsed(dirname)

      expect([feature.status.key, feature.slug, feature.archived_on, feature.canonical?]).to eq([key, slug, date, canonical])
    end
  end

  it "renames an old spelling to the new one, keeping the slug" do
    feature = parsed("003.00-⭐️--tax-rule-dsl")

    expect(feature.dirname_as(feature.status)).to eq("003.00━━⭐━━❯tax-rule-dsl")
  end

  it "keeps the archive date across a rename in place" do
    feature = parsed("002.00━━✅━━❯[2026-10-13]━━dev-foundation")

    expect(feature.dirname_as(OpenLanes::Plans::STATUS_BY_KEY.fetch(:deployed)))
      .to eq("002.00━━😎━━❯[2026-10-13]━━dev-foundation")
  end

  it "drops the date when asked to" do
    feature = parsed("002.00━━✅━━❯[2026-10-13]━━dev-foundation")

    expect(feature.dirname_as(feature.status, archived_on: nil)).to eq("002.00━━✅━━❯dev-foundation")
  end
end
