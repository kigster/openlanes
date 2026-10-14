# frozen_string_literal: true

# Backs `/spec-create <name of the spec>`.
RSpec.describe OpenLanes::Lifecycle::Creator, :tree do
  subject(:creator) { described_class.new(dir: plans_root) }

  let(:created) { File.basename(creator.create(words:).value!) }
  let(:words) { %w[tax rule dsl] }

  describe "#create" do
    context "with an empty tree" do
      it "starts at 000.00 and opens in the spec phase" do
        expect(created).to eq("000.00━━⚪━━❯tax-rule-dsl")
      end
    end

    context "with plans already present" do
      let!(:tree) do
        plans do |t|
          t.plan "001.00", :new, "initial-spec", files: { "spec.md" => spec_body }
          t.plan "002.00", :approved, "dev-foundation", prs: [t.merged(2, "Ship it")]
        end
      end

      it "takes the next whole number, padded to .00" do
        expect(created).to eq("003.00━━⚪━━❯tax-rule-dsl")
      end

      it "creates the directory on disk" do
        expect(File.directory?(creator.create(words:).value!)).to be(true)
      end

      it "allocates past a number that lives only in an inactive subfolder" do
        plans { |t| t.plan "007.00", :approved, "archived", under: "archive", archived_on: Date.new(2026, 9, 1) }

        expect(created).to eq("008.00━━⚪━━❯tax-rule-dsl")
      end

      it "ignores retroactive siblings when choosing the next number" do
        plans { |t| t.plan "002.01", :approved, "backfill", prs: [t.merged(9, "x")] }

        expect(created).to eq("003.00━━⚪━━❯tax-rule-dsl")
      end
    end

    describe ".topic" do
      it "names a plan after the idea's opening heading, not the heading and its paragraph" do
        idea = "# Minesweeper\n\nMinesweeper is played on a grid of covered squares.\n"
        expect(described_class.slugify(described_class.topic(idea))).to eq("minesweeper")
      end

      it "prefers a frontmatter title" do
        idea = "---\ntitle: web based minesweeper game\n---\nBuild a classic Minesweeper game that runs in the browser.\n"
        expect(described_class.topic(idea)).to eq(%w[web based minesweeper game])
      end

      it "takes the first eight words of a plain first line" do
        expect(described_class.topic("\n  Export the ledger as CSV for the accountant every month\nmore"))
          .to eq(%w[Export the ledger as CSV for the accountant])
      end

      it "skips frontmatter that is not YAML" do
        expect(described_class.topic("---\n: [\n---\nBody text")).to eq(%w[Body text])
      end
    end

    describe "slugification" do
      it "lowercases, joins on hyphens and drops punctuation" do
        aggregate_failures do
          expect(described_class.slugify(["Tax Rule DSL"])).to eq("tax-rule-dsl")
          expect(described_class.slugify(%w[Multi-Tenant Billing!])).to eq("multi-tenant-billing")
          expect(described_class.slugify(["  spaced   out  "])).to eq("spaced-out")
        end
      end

      it "refuses a topic that slugifies to nothing, rather than making a folder called '-'" do
        expect(creator.create(words: ["!!!"])).to be_failure
      end
    end

    context "when the same topic is created twice" do
      let!(:tree) { plans { |t| t.plan "001.00", :new, "tax-rule-dsl", files: { "spec.md" => spec_body } } }

      it "gives the second one its own number rather than colliding" do
        expect(created).to eq("002.00━━⚪━━❯tax-rule-dsl")
      end

      it "never overwrites the folder that is already there" do
        creator.create(words:)

        expect(File.exist?(File.join(plans_root, "001.00━━⚪━━❯tax-rule-dsl", "spec.md"))).to be(true)
      end
    end
  end

  describe "#create with :after — a plan written after the fact" do
    let!(:tree) do
      plans do |t|
        t.plan "001.00", :new, "initial-spec", files: { "spec.md" => spec_body }
        t.plan "002.00", :approved, "dev-foundation", prs: [t.merged(2, "Ship it")]
        t.plan "003.00", :new, "tenancy", files: { "spec.md" => spec_body }
      end
    end

    let(:retro) { File.basename(creator.create(words: %w[schedule k1 backfill], after: "002").value!) }

    it "takes a decimal slot in the gap, so the number itself records the retroactivity" do
      expect(retro).to eq("002.01━━⏪━━❯schedule-k1-backfill")
    end

    it "takes the next free slot when the gap is already partly used" do
      plans { |t| t.plan "002.01", :retroactive, "earlier-backfill", prs: [t.merged(8, "x")] }

      expect(retro).to eq("002.02━━⏪━━❯schedule-k1-backfill")
    end

    it "accepts the anchor in either shape" do
      expect(File.basename(creator.create(words: %w[a b], after: "002.00").value!)).to start_with("002.01━━")
    end

    it "refuses to anchor against a plan that does not exist" do
      expect(creator.create(words: %w[a b], after: "099")).to be_failure
    end

    it "births retroactive plans as ⏪, since the work exists but the documents do not" do
      expect(retro).to include("⏪")
    end
  end

  describe "an explicit status" do
    it "honours one when given, rather than always opening at ⚪" do
      expect(File.basename(creator.create(words:, status: "planned").value!)).to eq("000.00━━⭐━━❯tax-rule-dsl")
    end

    it "rejects a status it does not recognise" do
      expect(creator.create(words:, status: "chartreuse")).to be_failure
    end
  end

  # `create --prs` documents work that already shipped. ⏪ Retroactive means
  # "the feature is live, but has neither a specification nor a plan", and its
  # invariant demands recorded pull requests and no spec.md — which is exactly
  # and only what this produces.
  describe "creating from pull requests" do
    let(:prs) do
      [{ number: 12, title: "Add health checks", url: "https://github.com/o/r/pull/12",
        state: "Merged 🟣", body: "Adds /healthz and /readyz." },
       { number: 15, title: "Structured logging", url: "https://github.com/o/r/pull/15",
        state: "Merged 🟣", body: "JSON lines." }]
    end

    let!(:anchor) { plans { |t| t.plan "018.00", :approved, "deploy", prs: [t.merged(1, "x")] } }

    let(:path) do
      described_class.new(dir: plans_root)
                     .create(words: %w[alerting probes], after: "018", prs:).value!
    end

    it "records the pull requests in the folder it just made" do
      expect(File.read(File.join(path, "pull-requests.md"))).to include("/pull/12", "/pull/15")
    end

    it "opens at ⏪ Retroactive, in the gap after the plan the work landed on" do
      expect(File.basename(path)).to eq("018.01━━⏪━━❯alerting-probes")
    end

    # The point of the whole design: the folder is not merely labelled
    # retroactive, its contents justify the label the moment it exists.
    it "is justified by its contents rather than merely claiming to be" do
      expect(OpenLanes::Plans::Subject.new(OpenLanes::Plans::Feature.parse(path))).to be_consistent
    end

    it "leaves spec.md unwritten — that is the writer's job, not the creator's" do
      expect(File.exist?(File.join(path, "spec.md"))).to be(false)
    end

    it "writes no pull-requests.md when there are no pull requests to record" do
      plain = described_class.new(dir: plans_root).create(words: %w[ordinary work]).value!

      expect(Dir.children(plain)).to eq(["state.json"])
    end

    it "starts the plan's state.json with the state it opened in" do
      plain = described_class.new(dir: plans_root).create(words: %w[ordinary work]).value!

      expect(OpenLanes::Plans::PlanState.for(plain).state).to eq("new")
    end
  end
end
