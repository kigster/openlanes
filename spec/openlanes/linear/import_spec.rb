# frozen_string_literal: true

# The import decides everything from disk. That is the property worth
# protecting: `--dry-run` is only honest because the dry run and the push
# consume the same object, so what gets printed and what gets sent cannot
# disagree. Everything needing the network — the project, the repository's
# pull requests — is handed in.
RSpec.describe OpenLanes::Linear::Import, :tree do
  subject(:import) do
    described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), team: "TAX", project:, **options)
  end

  let(:options) { {} }
  let(:project) { { "id" => "p-1", "name" => "US Tax Law: Self Contained Ruby Gem", "url" => "https://linear.app/p-1" } }

  let!(:tree) do
    plans do |t|
      t.plan "001.00",
        :new,
        "initial-spec",
        files: { "spec.md" => spec_body(title: "Answer one question", goal: "Make it work.") }
      t.plan "002.00",
        :approved,
        "dev-foundation",
        files: { "spec.md" => spec_body(title: "Dev Foundation"),
                 "plan.md" => "## PR-1 — Test rig\n\nThe rig.\n\n## PR-2 — Rails foundation\n\nThe app.\n" },
        prs:   [t.merged(2, "Spec 002 PR-1: Test rig"), t.merged(3, "Spec 002 PR-2: Rails foundation")]
      t.plan "003.00", :blocked, "pricing", files: { "blocked.md" => "B1. Which tier?" }
    end
  end

  describe "the shape it proposes" do
    # One folder, one issue. The units inside its plan.md are that issue's
    # children — not projects, which are yours and which this never creates.
    it "gives every plan an issue, and every work unit a child of it" do
      expect(import.actions.map { |a| [a.ordinal, a.kind, a.unit] }).to eq(
        [["001.00", :issue, "PLAN"],
         ["002.00", :issue, "PLAN"], ["002.00", :subissue, "PR-1"], ["002.00", :subissue, "PR-2"],
         ["003.00", :issue, "PLAN"]]
      )
    end

    it "files everything under the project it was given" do
      expect(import.actions.map { |a| a.args[:project] }.uniq).to eq(["US Tax Law: Self Contained Ruby Gem"])
    end

    it "proposes no project of its own, whatever the plans look like" do
      expect(import.actions.map(&:kind).uniq).to match_array(%i[issue subissue])
    end

    it "numbers a plan's own issue, so it can be found by plan" do
      plan = import.actions.find { |a| a.ordinal == "001.00" }

      expect(plan.title).to eq("[001.00] Answer one question")
    end

    # The parent already says which plan. Repeating it on every child is
    # noise, and "PR-1" is this tool's key for a section of plan.md — it
    # means nothing to anyone reading Linear.
    it "leaves both the plan number and its own unit key out of a child's title" do
      child = import.actions.find { |a| a.unit == "PR-1" }

      expect(child.title).to eq("Test rig")
    end
  end

  describe "the arguments it emits" do
    let(:child) { import.actions.find { |a| a.unit == "PR-1" } }

    # They are the Linear MCP server's own argument names on purpose: the same
    # JSON has to drive both transports, or the two will drift.
    it "addresses everything by the names a human already knows" do
      expect(child.args).to include(team: "TAX",
        project: a_string_including("Ruby Gem"),
        state: "Done",
        labels: [])
    end

    it "attaches the pull requests rather than listing them in the body" do
      aggregate_failures do
        expect(child.args[:links]).to eq([{ url:   "https://github.com/example/repo/pull/2",
                                            title: "#2 — Spec 002 PR-1: Test rig" }])
        expect(child.args[:description]).not_to include("/pull/2")
      end
    end

    it "points back at the folder, so a reader can find the source of truth" do
      expect(child.args[:description]).to include("`.plans/002.00━━✅━━❯dev-foundation`", "unit `PR-1`")
    end

    # A plan in 🟡 Building has some units merged and some not started.
    # Giving them all the plan's state says they are all in progress, which
    # is false about most of them and useless on a board.
    it "takes a child's state from its own pull requests, not from the plan" do
      plans do |t|
        t.plan "004.00",
          :building,
          "half-done",
          files: { "spec.md" => spec_body, "plan.md" => "## PR-1 — Done bit\n\n## PR-2 — Open bit\n" },
          prs:   [t.merged(7, "Spec 004 PR-1: Done bit"), t.open(8, "Spec 004 PR-2: Open bit")]
      end
      states = import.actions.select { |a| a.ordinal == "004.00" && a.child? }.map { |a| a.args[:state] }

      expect(states).to eq(["Done", "In Review"])
    end

    it "gives a childless plan the plan's own state" do
      blocked = import.actions.find { |a| a.ordinal == "003.00" }

      expect(blocked.args).to include(state: "Todo", labels: %w[blocked])
    end
  end

  describe "deciding between create, update and skip" do
    def record(dirname, digest:, unit: "PR-1", identifier: "TAX-41")
      File.write(File.join(plans_root, dirname, "linear.md"),
        OpenLanes::Linear::Issues.render(team: "TAX",
          project: { name: project["name"], url: project["url"] },
          issues: [OpenLanes::Linear::Issue.new(unit:,
            identifier:,
            url: "https://linear.app/i",
            title: "t",
            state: "Done",
            digest:)]))
    end

    def digest_of(unit)
      described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), team: "TAX", project:)
                     .actions.find { |a| a.unit == unit }.digest
    end

    it "creates what no linear.md has ever heard of" do
      expect(import.actions).to all(have_attributes(op: :create))
    end

    it "skips an issue whose fingerprint still matches the plan" do
      record("002.00━━✅━━❯dev-foundation", digest: digest_of("PR-1"))

      expect(import.actions.find { |a| a.unit == "PR-1" }).to have_attributes(op: :skip, identifier: "TAX-41")
    end

    it "updates an issue whose plan has changed underneath it" do
      record("002.00━━✅━━❯dev-foundation", digest: "deadbeef")
      action = import.actions.find { |a| a.unit == "PR-1" }

      aggregate_failures do
        expect(action.op).to eq(:update)
        expect(action.args).to include(id: "TAX-41")
        expect(action.args.keys).not_to include(:team, :project)
      end
    end

    # A pull request raised after the first import must still reach its issue,
    # and Linear keys an attachment on its URL, so re-sending is an update.
    it "still sends the pull requests on an update" do
      record("002.00━━✅━━❯dev-foundation", digest: "deadbeef")

      expect(import.actions.find { |a| a.unit == "PR-1" }.args[:links]).to include(hash_including(url: %r{/pull/2}))
    end

    it "hangs a child off the parent linear.md already names" do
      record("002.00━━✅━━❯dev-foundation", digest: "deadbeef", unit: "PLAN", identifier: "TAX-40")

      expect(import.actions.find { |a| a.unit == "PR-1" }.args).to include(parentId: "TAX-40")
    end

    context "with --update-unchanged" do
      let(:options) { { update_unchanged: true } }

      it "updates even what it would otherwise have left alone" do
        record("002.00━━✅━━❯dev-foundation", digest: digest_of("PR-1"))

        expect(import.actions.find { |a| a.unit == "PR-1" }).to have_attributes(op: :update, reason: "--update-unchanged")
      end
    end
  end

  describe "pull requests attributed to a folder from outside it" do
    let(:options) { { adopted: { "002.00━━✅━━❯dev-foundation" => [orphan] } } }
    let(:orphan) do
      OpenLanes::Plans::PullRequest.new(number: "91",
        title: "Wire the rig to CI",
        url: "https://github.com/example/repo/pull/91",
        state: "Merged 🟣")
    end

    it "gives it a child of its own, since no declared unit claims it" do
      expect(import.actions.map(&:unit)).to include("#91")
    end

    it "titles that child from the pull request" do
      expect(import.actions.find { |a| a.unit == "#91" }.title).to eq("Wire the rig to CI")
    end

    it "never gives one pull request two issues" do
      claimed = import.actions.flat_map { |a| a.args[:links].to_a.map { |l| l[:url] } }

      expect(claimed).to eq(claimed.uniq)
    end
  end

  describe "choosing which plans to import" do
    it "skips everything numbered below --since" do
      filtered = described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root),
        team: "TAX",
        project:,
        since: "002.00")

      expect(filtered.actions.map(&:ordinal).uniq).to eq(%w[002.00 003.00])
    end

    it "keeps only the states asked for" do
      filtered = described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root),
        team: "TAX",
        project:,
        statuses: [:blocked])

      expect(filtered.actions.map(&:ordinal).uniq).to eq(%w[003.00])
    end
  end

  describe "a plan whose state nobody has decided how to file" do
    before do
      plans do |t|
        t.plan "009.00", :shit, "scrapped-work", files: { "rewrite.md" => "Start again." }
        t.plan "010.00", :rolled_back, "pulled", files: { "rollback.md" => "It broke checkout." }
      end
    end

    it "proposes nothing for it" do
      expect(import.actions.map(&:ordinal)).not_to include("009.00", "010.00")
    end

    # Skipping quietly and filing it somewhere plausible are the same failure
    # wearing different clothes: nobody finds out.
    it "reports it, grouped by the state that stopped it" do
      expect(import.unplaced.transform_keys(&:key)).to eq(shit: ["009.00"], rolled_back: ["010.00"])
    end
  end

  describe "#to_json" do
    it "emits the team, the project and every action for the MCP transport" do
      parsed = JSON.parse(import.to_json)

      aggregate_failures do
        expect(parsed["team"]).to eq("TAX")
        expect(parsed["project"]).to eq("US Tax Law: Self Contained Ruby Gem")
        expect(parsed["actions"].size).to eq(import.actions.size)
      end
    end
  end
end
