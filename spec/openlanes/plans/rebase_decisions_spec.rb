# frozen_string_literal: true

# 036.00: bb8-resolver tags its judgement calls under ## Rebase decisions,
# and palpatine signs manual while any of them is unanswered.
RSpec.describe OpenLanes::Plans::RebaseDecisions do
  let(:plan_md) do
    <<~MD
      # Plan 008.01

      ## Backend

      - [semantic-fork] not a rebase decision, so never read

      ## Rebase decisions

      - [duplicate-implementation] lib/a.rb: main built the same parser; kept main's. Answer: unanswered
      - [refactor-collision] lib/b.rb: main extracted the helper we patched;
        re-applied the guard there. Answer: confirmed
      - [semantic-fork] lib/c.rb: main returns nil where we raised; kept ours. Answer: **overridden**
      - lib/d.rb: kept both imports.
      - [semantic-fork] lib/e.rb: no answer written yet

      ## Task completed when

      - [refactor-collision] also not a decision
    MD
  end

  let(:entries) { described_class.parse(plan_md) }

  it "reads every entry under the heading, and nothing outside it" do
    expect(entries.map(&:kind)).to eq(["duplicate-implementation", "refactor-collision", "semantic-fork", nil, "semantic-fork"])
  end

  it "reads each answer" do
    expect(entries.map(&:answer)).to eq([:unanswered, :confirmed, :overridden, nil, :unanswered])
  end

  it "folds a continuation line into its entry" do
    expect(entries[1].text).to eq("lib/b.rb: main extracted the helper we patched; re-applied the guard there. Answer: confirmed")
  end

  it "counts an untagged entry as an ordinary resolution, not a judgement call" do
    aggregate_failures do
      expect(entries[3]).not_to be_tagged
      expect(entries[3]).not_to be_unanswered
      expect(entries[3].to_s).to eq("lib/d.rb: kept both imports.")
    end
  end

  it "counts a tagged entry with no Answer as unanswered" do
    expect(entries.last).to be_unanswered
  end

  describe ".unanswered" do
    it "answers only the tagged entries no person confirmed or overridden" do
      expect(described_class.unanswered(plan_md).map(&:text))
        .to eq(["lib/a.rb: main built the same parser; kept main's. Answer: unanswered", "lib/e.rb: no answer written yet"])
    end

    it "answers nothing when every call is confirmed or overridden" do
      cleared = plan_md.gsub("Answer: unanswered", "Answer: confirmed").sub("no answer written yet", "Answer: overridden")

      expect(described_class.unanswered(cleared)).to be_empty
    end

    it "answers nothing for a plan with no rebase decisions" do
      expect(described_class.unanswered("# Plan\n\n## Backend\n")).to be_empty
    end
  end

  it "reads a tag outside KINDS as untagged" do
    expect(described_class.parse("## Rebase decisions\n\n- [whatever] lib/x.rb: hm\n").first).not_to be_tagged
  end

  it "reads a second Rebase decisions section from a later rebase" do
    md = "## Rebase decisions\n\n- [semantic-fork] a\n\n## Notes\n\n- x\n\n## Rebase decisions\n\n1. [refactor-collision] b\n"

    expect(described_class.parse(md).map(&:kind)).to eq(%w[semantic-fork refactor-collision])
  end

  it "quotes a tagged entry with its kind and answer, as a prompt shows it" do
    expect(entries.first.to_s).to start_with("[duplicate-implementation] lib/a.rb").and end_with("(unanswered)")
  end

  it "names the three judgement-call kinds both prompts quote" do
    expect(described_class::KINDS).to eq(%w[duplicate-implementation refactor-collision semantic-fork])
  end

  # The prompt is markdown and cannot interpolate KINDS, so this keeps it honest.
  it "is quoted kind for kind by palpatine's hard trigger" do
    prompt = File.read(File.expand_path("../../../agents/palpatine-risk-assessor.md", __dir__))

    expect(prompt).to include("An unanswered rebase decision", *described_class::KINDS.map { "`#{it}`" })
  end

  it "writes its format with a tag the parser reads back" do
    expect(described_class.parse("## Rebase decisions\n\n#{described_class::FORMAT.sub("<kind>", "semantic-fork")}\n").first)
      .to have_attributes(kind: "semantic-fork", answer: :unanswered)
  end
end
