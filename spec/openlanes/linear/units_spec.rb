# frozen_string_literal: true

# Every example here comes from a plan that is really on disk somewhere. The
# parser was written against one convention, run over thirty-eight plans, and
# rewritten twice — these are the shapes that broke it.
RSpec.describe OpenLanes::Linear::Units, :tree do
  subject(:units) { described_class.new(subject: OpenLanes::Plans::Tree.new(dir: plans_root).find(ordinal)).all }

  let(:ordinal) { "010.00" }

  def build(plan, ordinal: "010.00", prs: nil)
    plans do |t|
      t.plan ordinal,
        :building,
        "engine-advanced",
        files: { "spec.md" => spec_body, "plan.md" => plan },
        prs:   prs || [t.merged(25, "Spec 010 PR-1: Per-person taxes")]
    end
  end

  context "when the units are headed at level two and repeated at level three" do
    before do
      build(<<~PLAN)
        # Plan 010

        ## Conventions binding all three PRs

        ## PR-1 (010a) — Per-person taxes: SE tax, NIIT

        The substrate.

        ### PR-1 parameters

        Rates and thresholds.

        ### PR-1 tests

        Boundary-positioned.

        ## PR-2 (010b) — MAGI registry, QBI

        The registry.
      PLAN
    end

    # The bug this replaces turned three units into nine: every heading that
    # mentioned a pull request started a new one.
    it "finds one unit per pull request, not one per heading that mentions it" do
      expect(units.map(&:key)).to eq(%w[PR-1 PR-2])
    end

    it "keeps the deeper headings as the unit's contents" do
      expect(units.first.body).to include("PR-1 parameters", "Boundary-positioned")
    end

    it "takes the title from the unit's own heading, not from its continuations" do
      expect(units.first.title).to eq("Per-person taxes: SE tax, NIIT")
    end
  end

  context "when the units are headed at level three, as plans that use level two for prose do" do
    let(:ordinal) { "020.00" }

    before do
      build(<<~PLAN, ordinal: "020.00", prs: nil)
        # Plan 020

        ## Pull requests

        ### PR 020.01 — Clerk authentication behind the dev-fixture seam (✔ #38)

        The seam.

        ### PR 020.02 — Frontend: Clerk sign-in (▶︎ in-flight)

        The screen.
      PLAN
    end

    it "reads the shallowest level that names a pull request, whichever level that is" do
      expect(units.map(&:key)).to eq(%w[PR-1 PR-2])
    end

    # `PR 020.01` is `PR-1` with the plan's own number glued on the front.
    it "normalises a unit numbered from the plan's number back to its position" do
      expect(units.map(&:key)).not_to include("PR-020.01")
    end

    it "strips the progress glyph from the title, since Linear tracks that itself" do
      expect(units.map(&:title)).to eq(["Clerk authentication behind the dev-fixture seam", "Frontend: Clerk sign-in"])
    end
  end

  describe "matching pull requests to units" do
    # Neither title says "PR-1". The heading is the only join there is, and it
    # is the join the plans that number their units 020.0n actually use.
    it "believes the pull request number written into the heading" do
      plans do |t|
        t.plan "020.00",
          :building,
          "clerk-integration",
          files: { "spec.md" => spec_body, "plan.md" => <<~PLAN },
            ### PR 020.01 — Clerk auth (✔ #38)

            ### PR 020.02 — Frontend (✔ #39)
          PLAN
          prs:   [t.merged(38, "Clerk authentication behind the dev-fixture seam"),
                  t.merged(39, "Frontend: Clerk sign-in + mockup design system")]
      end
      found = described_class.new(subject: OpenLanes::Plans::Tree.new(dir: plans_root).find("020.00")).all

      expect(found.map { |u| u.pull_requests.map(&:number) }).to eq([["38"], ["39"]])
    end

    it "believes a pull request title that names the unit" do
      build(<<~PLAN, prs: nil)
        ## PR-1 — Per-person taxes

        ## PR-2 — MAGI registry
      PLAN

      expect(units.map { |u| u.pull_requests.map(&:number) }).to eq([["25"], []])
    end

    # There is nowhere else for them to go. That is arithmetic, not a guess.
    it "gives every pull request to the only unit there is" do
      build(<<~PLAN, prs: nil)
        ## PR-1 — The whole thing
      PLAN

      expect(units.first.pull_requests.map(&:number)).to eq(["25"])
    end

    it "never gives one pull request to two units" do
      plans do |t|
        t.plan "011.00",
          :building,
          "twice",
          files: { "spec.md" => spec_body, "plan.md" => "## PR-1 — One\n\n## PR-2 — Two\n" },
          prs:   [t.merged(9, "Spec 011 PR-1 and PR-2: both at once")]
      end
      found = described_class.new(subject: OpenLanes::Plans::Tree.new(dir: plans_root).find("011.00")).all

      expect(found.flat_map { |u| u.pull_requests.map(&:number) }).to eq(["9"])
    end
  end

  describe "a plan that never divided itself" do
    def units_of(ordinal) = described_class.new(subject: OpenLanes::Plans::Tree.new(dir: plans_root).find(ordinal)).all

    # Its own issue still exists — the folder always gets one. What it has no
    # business inventing is a child standing for the same thing.
    it "has no units at all when nothing has been planned or built" do
      plans do |t|
        t.plan "012.00", :new, "small-thing", files: { "spec.md" => spec_body(title: "Small Thing") }
      end

      expect(units_of("012.00")).to be_empty
    end

    # A pull request that shipped is a unit of work whether or not anybody
    # wrote it down first. This is the retroactive case.
    it "takes one unit per pull request when it declared none itself" do
      plans do |t|
        t.plan "013.00",
          :approved,
          "shipped-anyway",
          prs: [t.merged(4, "[013.00] Ship the thing"), t.merged(5, "Ship the other thing")]
      end

      expect(units_of("013.00").map(&:key)).to eq(["#4", "#5"])
    end

    it "strips the plan number this tool put on the pull request title" do
      plans do |t|
        t.plan "013.00", :approved, "shipped-anyway", prs: [t.merged(4, "[013.00] Ship the thing")]
      end

      expect(units_of("013.00").first.title).to eq("Ship the thing")
    end
  end

  # `plan.md` files are full of shell and SQL whose comments open with `#`.
  it "ignores headings inside a fenced block, which are not headings at all" do
    build(<<~PLAN)
      ## PR-1 — The real unit

      ```bash
      ## PR-2 — not a unit, a comment in a script
      ```

      Still PR-1.
    PLAN

    expect(units.map(&:key)).to eq(["PR-1"])
  end
end
