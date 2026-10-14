# frozen_string_literal: true

# Backs `/spec-status` — the table of every feature, its status in words and
# icon, and its pull requests as clickable links.
RSpec.describe OpenLanes::Presentation::Reporter, :tree do
  subject(:reporter) { described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root)) }

  let!(:tree) do
    plans do |t|
      t.plan "001.00", :new, "initial-spec", files: { "spec.md" => spec_body(title: "Initial Spec") }
      t.plan "002.00",
        :approved,
        "dev-foundation",
        files: { "spec.md" => spec_body },
        prs:   [t.merged(2, "Frontend test rig"), t.merged(3, "Rails foundation")]
      t.plan "018.01",
        :building,
        "verify-returns",
        files: { "spec.md" => spec_body, "plan.md" => "# Plan" },
        prs:   [t.open(92, "Send mail through Resend")]
      t.plan "003.00", :blocked, "pricing", files: { "blocked.md" => "B1. Which tier?" }
    end
  end

  let(:table) { reporter.render }

  describe "#render" do
    it "lists every plan in number order, retroactive siblings in their gap" do
      expect(table.scan(/\b\d{3}\.\d{2}\b/)).to eq(%w[001.00 002.00 003.00 018.01])
    end

    it "shows each status as both icon and words" do
      aggregate_failures do
        expect(table).to include("⚪️").and include("New")
        expect(table).to include("✅").and include("Approved & Merged")
        expect(table).to include("🟡").and include("Building")
        expect(table).to include("⭕️").and include("Technical Block")
      end
    end

    it "leaves two spaces after each icon, so a wide emoji cannot overlap the words" do
      aggregate_failures do
        expect(table).to include("🟡  Building")
        expect(table).to match(/🟡  1\b/)
      end
    end

    it "renders the feature name from the slug" do
      expect(table).to include("Dev Foundation")
    end

    it "makes pull requests clickable" do
      expect(table).to include("https://github.com/example/repo/pull/92")
    end

    it "shows every pull request a plan records, not just the first" do
      aggregate_failures do
        expect(table).to include("/pull/2")
        expect(table).to include("/pull/3")
      end
    end

    # The table colours itself when attached to a terminal, and colour hides
    # content from naive matchers: `\b\d{3}\.\d{2}\b` does NOT match "001.00"
    # inside "\e[1m001.00\e[0m", because the escape ends in "m" — a word
    # character — so there is no word boundary before the digits.
    #
    # That is exactly the bug this example exists to catch: the suite forces
    # colour off for determinism, which means nothing else here would ever
    # exercise the coloured path.
    it "still lists every plan when colour is on" do
      allow(OpenLanes::UI).to receive(:color?).and_return(true)
      OpenLanes::UI.reset!

      rendered = reporter.render

      aggregate_failures do
        expect(rendered).to match(/\e\[/), "expected colour to actually be on"
        expect(strip_ansi(rendered).scan(/\b\d{3}\.\d{2}\b/)).to eq(%w[001.00 002.00 003.00 018.01])
      end
    end

    it "says so plainly when a plan has no pull requests yet" do
      expect(table).to match(/001\.00.*(—|none|no PRs)/i)
    end
  end

  describe "counts" do
    it "totals plans by status" do
      expect(reporter.totals).to include(approved: 1, new: 1, building: 1, blocked: 1)
    end
  end

  describe "consistency" do
    let!(:tree) do
      plans { |t| t.plan "001.00", :approved, "lying", prs: [t.open(5, "still open")] }
    end

    it "flags a plan whose status its contents do not justify" do
      expect(reporter.inconsistent.map { |s| s.feature.ordinal.to_s }).to eq(["001.00"])
    end

    it "explains what is wrong, not merely that something is" do
      expect(reporter.inconsistent.first.violation).to include("1 pull request still open")
    end

    # The violation must reach the rendered table itself — a reader of
    # `list-plans` never calls #inconsistent, so a table without the arrow
    # line simply looks fine.
    it "prints the violation under the plan's own row" do
      expect(table).to match(/↳ .*1 pull request still open/)
    end

    it "counts the liars in the footer, so the problem survives scrolling" do
      expect(table).to include("1 with a status their contents do not justify")
    end
  end

  describe "duplicate plan numbers" do
    let!(:tree) do
      plans do |t|
        t.plan "002.00", :new, "one-thing", files: { "spec.md" => spec_body }
        t.plan "002.00", :blocked, "another-thing", files: { "blocked.md" => "B1" }
      end
    end

    # A number is an identity that branches and PR titles join on. Two folders
    # wearing it makes every one of those joins ambiguous.
    it "names the number and every folder claiming it" do
      aggregate_failures do
        expect(table).to include("002.00 is claimed by 2 folders")
        expect(table).to include("002.00-⚪️ → one-thing")
        expect(table).to include("002.00-⭕️ → another-thing")
      end
    end
  end

  describe "an empty tree" do
    let!(:tree) { plans }

    it "says the tree is empty rather than printing a headerless table" do
      expect(table).to match(/no plans/i)
    end
  end

  describe "table discipline" do
    it "writes nothing to STDERR, so the table composes in a pipe" do
      expect { reporter.render }.not_to output.to_stderr
    end
  end
end
