# frozen_string_literal: true

RSpec.describe OpenLanes::Evals::Check, :tree do
  subject(:verdict) { described_class.new(kind:, name: "the check", args:).call(evidence) }

  let(:folder) do
    File.join(plans_root, "plan").tap do |dir|
      FileUtils.mkdir_p(dir)
      files.each { |name, body| File.write(File.join(dir, name), body) }
    end
  end
  let(:files) { { "spec.md" => spec_md } }
  let(:spec_md) do
    <<~MD
      # Retry

      ## Research

      One two three four five, see https://example.com/a and https://example.com/b.

      ### Could not settle

      1. Idempotency.

      ## Next

      After the research.

      > [!NOTE]
      >
      > [2026-09-04 11:29:20 AM PDT] [ agent: researcher   status: Completed, round 1 (approved) ]
    MD
  end
  let(:agent) { OpenLanes::Agents.find("researcher") }
  let(:state) { :researched }
  let(:run) { OpenLanes::Evals::Run.new(seconds: 61.6, tokens: 500) }
  let(:changes) { OpenLanes::Evals::Changes.new(paths: %w[lib/a.rb spec/a_spec.rb], lines: 12) }
  let(:evidence) { OpenLanes::Evals::Evidence.new(folder:, state:, agent:, run:, changes:) }

  def self.judges(kind, table)
    describe kind.to_s do
      let(:kind) { kind }

      table.each do |label, (args, ok, detail)|
        context label do
          let(:args) { args }

          it(ok ? "passes" : "fails") { expect([verdict.ok, verdict.detail]).to match([ok, detail]) }
        end
      end
    end
  end

  it "names the verdict after the check" do
    expect(described_class.new(kind: :file_exists, name: "has spec.md", args: { file: "spec.md" }).call(evidence).name)
      .to eq("has spec.md")
  end

  judges :state,
    "where it should be, and justified" => [{ expected: :researched }, true, /Researched/],
    "somewhere else"                    => [{ expected: :ready_for_planning }, false, "ended researched, expected ready_for_planning"]

  context "when the state's own invariant does not hold" do
    let(:spec_md) { "# Retry\n" }
    let(:kind) { :state }
    let(:args) { { expected: :researched } }

    it "fails with the invariant's reason" do
      expect(verdict.detail).to include("no `## Research` chapter")
    end
  end

  context "when nothing recorded the final state" do
    let(:state) { nil }
    let(:kind) { :state }
    let(:args) { { expected: :researched } }

    it "fails rather than guess" do
      expect(verdict.detail).to eq("the run recorded no final state")
    end
  end

  judges :signed,
    "Completed"                   => [{ note: nil }, true, "spec.md:17"],
    "Completed with the verdict"  => [{ note: "Approved" }, true, "spec.md:17"],
    "Completed with another note" => [{ note: "rejected" }, false, "signed Completed (approved), expected rejected"]

  context "when the agent stopped short" do
    let(:files) { { "spec.md" => "> [2026-09-04 11:29:20 AM PDT] [ agent: researcher   status: Started, round 1 ]\n" } }
    let(:kind) { :signed }
    let(:args) { { note: nil } }

    it "fails on the last entry" do
      expect(verdict.detail).to eq("last entry says Started")
    end
  end

  context "when the agent never signed" do
    let(:files) { { "spec.md" => "# Retry\n" } }
    let(:kind) { :signed }
    let(:args) { { note: nil } }

    it "names the documents it should have signed" do
      expect(verdict.detail).to eq("researcher signed none of spec.md")
    end
  end

  judges :file_exists,
    "a file that is there" => [{ file: "spec.md" }, true, "present"],
    "a file that is not"   => [{ file: "plan.md" }, false, "plan.md is missing"]

  judges :file_absent,
    "a file that is not there" => [{ file: "plan.md" }, true, "absent"],
    "a file that is"           => [{ file: "spec.md" }, false, "spec.md is still there"]

  judges :sections,
    "headings at any level"  => [{ file: "spec.md", headings: ["Research", "could not settle"] }, true, "all 2 present"],
    "a heading that is not"  => [{ file: "spec.md", headings: %w[Research Goal] }, false, "missing ## Goal"],
    "a prefix of a heading"  => [{ file: "spec.md", headings: %w[Res] }, false, "missing ## Res"],
    "a file that is missing" => [{ file: "plan.md", headings: %w[Goal] }, false, "plan.md is missing"]

  judges :contains,
    "a literal"              => [{ file: "spec.md", text: "example.com/a" }, true, "found"],
    "a pattern"              => [{ file: "spec.md", text: "/[Ii]dempoten/" }, true, "found"],
    "a literal that is not"  => [{ file: "spec.md", text: "Goal" }, false, "spec.md does not mention Goal"],
    "a file that is missing" => [{ file: "plan.md", text: "x" }, false, "plan.md is missing"]

  judges :excludes,
    "text that is not there" => [{ file: "spec.md", text: "TODO" }, true, "not found"],
    "text that is"           => [{ file: "spec.md", text: "Idempotency" }, false, "spec.md still says Idempotency"],
    "a file that is missing" => [{ file: "plan.md", text: "x" }, true, "plan.md is absent"]

  judges :changed,
    "a glob something matches" => [{ glob: "spec/**/*_spec.rb" }, true, "spec/a_spec.rb"],
    "a glob nothing matches"   => [{ glob: "web/*.js" }, false, "nothing matching web/*.js changed"]

  judges :untouched,
    "a glob nothing matches"   => [{ glob: "Gemfile" }, true, "untouched"],
    "a glob something matches" => [{ glob: "lib/**" }, false, "changed lib/a.rb"]

  # The section runs to the next heading of its own level, so ### children
  # count and the ledger, which is bookkeeping, never does.
  judges :words,
    "a section within bounds"   => [{ file: "spec.md", section: "Research", min: 5, max: 25 }, true, "20 words"],
    "a section too short"       => [{ file: "spec.md", section: "Research", min: 50 }, false, "20 words, fewer than 50"],
    "a whole file too long"     => [{ file: "spec.md", max: 5 }, false, /more than 5/],
    "a section that is missing" => [{ file: "spec.md", section: "Goal", min: 1 }, false, "spec.md has no ## Goal"],
    "a file that is missing"    => [{ file: "plan.md", min: 1 }, false, "plan.md is missing"]

  judges :count,
    "links within bounds" => [{ file: "spec.md", section: "Research", pattern: "https?://", min: 1, max: 2 }, true, "2 matches"],
    "too few links"       => [{ file: "spec.md", section: "Research", pattern: "https?://", min: 5 }, false, "2 matches, fewer than 5"]

  judges :changed_files,
    "within bounds" => [{ min: 1, max: 2 }, true, "2 files changed"],
    "too many"      => [{ max: 1 }, false, "2 files changed, more than 1"]

  judges :changed_lines,
    "within bounds" => [{ min: 1, max: 20 }, true, "12 lines changed"],
    "too few"       => [{ min: 13 }, false, "12 lines changed, fewer than 13"]

  judges :seconds,
    "inside the budget" => [{ max: 62 }, true, "62 seconds"],
    "over the budget"   => [{ max: 60 }, false, "62 seconds, more than 60"]

  judges :tokens,
    "inside the budget" => [{ max: 500 }, true, "500 tokens"],
    "over the budget"   => [{ max: 499 }, false, "500 tokens, more than 499"]

  context "when no repository was recorded" do
    let(:changes) { nil }

    %i[changed untouched].each do |kind|
      it "fails #{kind} rather than pass it vacuously" do
        expect(described_class.new(kind:, name: "x", args: { glob: "*" }).call(evidence).detail).to eq("no repository was recorded")
      end
    end

    %i[changed_files changed_lines].each do |kind|
      it "fails #{kind}" do
        expect(described_class.new(kind:, name: "x", args: { max: 1 }).call(evidence).ok).to be(false)
      end
    end
  end

  context "when the run measured nothing" do
    let(:run) { OpenLanes::Evals::Run.new }

    %i[seconds tokens].each do |kind|
      it "fails #{kind}: a budget nobody measured was not kept" do
        expect(described_class.new(kind:, name: "x", args: { max: 1 }).call(evidence).detail).to eq("not measured")
      end
    end
  end

  describe ".for" do
    subject(:names) { described_class.for(kase).map(&:name) }

    let(:kase) do
      OpenLanes::Evals::Case.new(id: "x",
        agent: "researcher",
        depth: :fast,
        description: "",
        path: "/x.yml",
        fixture: OpenLanes::Evals::Case::Fixture.new(state: :new, slug: "x", files: {}, repo: {}),
        expect: {
          "signed" => "approved", "files_exist" => ["a.md"], "files_absent" => ["b.md"],
          "contains" => { "a.md" => %w[x y] }, "excludes" => { "a.md" => "z" },
          "changed_paths" => ["lib/**"], "untouched" => ["Gemfile"],
          "depth" => { "fast" => {
            "words" => [{ "file" => "a.md", "max" => 9 }, { "file" => "a.md", "section" => "S", "min" => 2 }],
            "count" => { "file" => "a.md", "pattern" => "x", "min" => 1, "max" => 3 },
            "changed_files" => { "max" => 2 }, "changed_lines" => { "min" => 1, "max" => 9 },
            "max_seconds" => 5, "max_tokens" => 6
          } }
        })
    end

    it "names every check the way a report reads it" do
      expect(names).to eq([
                            "signed Completed (approved)", "has a.md", "no b.md", "a.md contains x", "a.md contains y",
                            "a.md excludes z", "changed lib/**", "untouched Gemfile",
                            "words in a.md ≤ 9 @fast", "words in a.md#S ≥ 2 @fast", "count /x/ in a.md 1..3 @fast",
                            "changed files ≤ 2 @fast", "changed lines 1..9 @fast", "seconds ≤ 5 @fast", "tokens ≤ 6 @fast"
                          ])
    end
  end

  # An agent confined to one frontmatter line may write it and sign; anything
  # more is the author's spec rewritten under them.
  describe "spec_only" do
    let(:kind) { :spec_only }
    let(:original) { "---\ntitle: Parser consumer\n---\n\n# 050\n\nUses 034's parser.\n" }
    let(:args) { { before: { "spec.md" => original } } }
    let(:signed) do
      "\n> [!NOTE]\n>\n> [2026-10-16 10:00:00 AM PDT] [ agent: ewoki-linker   status: Completed, round 1 ]\n" \
        ">\n> 034.00: 050 calls the parser 034 builds.\n"
    end

    def linked(line) = original.sub("title: Parser consumer\n", "title: Parser consumer\n#{line}\n") + signed

    context "when only depends_on and a signed NOTE were added" do
      let(:files) { { "spec.md" => linked('depends_on: ["034.00"]'), "state.json" => "{}" } }

      it "passes" do
        expect(verdict.ok).to be(true)
        expect(verdict.detail).to eq('depends_on: ["034.00"]')
      end
    end

    context "when the plan needs nothing" do
      let(:files) { { "spec.md" => linked("depends_on: [none]") } }

      it("passes") { expect(verdict.ok).to be(true) }
    end

    context "when the value is an empty list" do
      let(:files) { { "spec.md" => linked("depends_on: []") } }

      it "fails, since [] reads as unanswered" do
        expect(verdict.ok).to be(false)
        expect(verdict.detail).to include("not [none] or quoted")
      end
    end

    context "when the spec body was edited too" do
      let(:files) { { "spec.md" => linked('depends_on: ["034.00"]').sub("Uses", "Needs") } }

      it "fails" do
        expect(verdict.ok).to be(false)
        expect(verdict.detail).to include('outside depends_on')
      end
    end

    context "when the value is an unquoted number" do
      let(:files) { { "spec.md" => linked("depends_on: [34]") } }

      it "fails" do
        expect(verdict.ok).to be(false)
        expect(verdict.detail).to include("not [none] or quoted")
      end
    end

    context "when plan.md was touched" do
      let(:files) { { "spec.md" => linked("depends_on: [none]"), "plan.md" => "# Plan\n" } }

      it "fails" do
        expect(verdict.ok).to be(false)
        expect(verdict.detail).to eq("changed plan.md")
      end
    end

    context "when no depends_on line was written" do
      let(:files) { { "spec.md" => original + signed } }

      it("fails") { expect(verdict.detail).to eq("spec.md has no depends_on: line") }
    end
  end
end
