# frozen_string_literal: true

require "json"
require "open3"

# Decisions N1-N5 end to end: a repository laid out the old way, driven
# through the real `exe/openlanes` in a subprocess, nothing stubbed. Each
# unit has its own specs; this one is what proves they agree with each other
# on a repository that has history.
RSpec.describe "migrating a repository's plan folders", :tree do
  let(:exe) { File.expand_path("../../exe/openlanes", __dir__) }
  let(:merged) { "| Pull Request Number | Pull Request Name | Status |\n| -: | :- | -: |\n| 1 | [x](https://github.com/example/repo/pull/1) | Merged 🟣 |\n" }

  # Each folder is committed under a 🟡 name, then renamed to its state, the
  # way the harness moves a plan, so git has a rename to date an archive by.
  let(:folders) do
    {
      "001-⚪️--dashes"            => { "spec.md" => spec_body },
      "002.00-⭐️-single"          => { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## Units\n" },
      "003.00-⭕️ → tech-block"    => { "blocked.md" => "## B1\n\nWhich database?\n" },
      "004.00-🅱️ → product-block" => { "blocked.md" => "## B1\n\nWhich colour?\n" },
      "005.00-✅ → shipped"        => { "spec.md" => spec_body, "pull-requests.md" => merged },
      "006.00-☢️ → parked"        => { "delayed.md" => "Revisit when the API ships.\n" },
      "007.00-❌ → dropped"        => { "discarded.md" => "Not needed.\n" },
      "008.00-🕰️ → backfill"      => { "pull-requests.md" => merged },
      "009.00-⚪️ → verified"      => { "spec.md" => "---\nhow-to-verify:\n  - just test\n---\n#{spec_body}" }
    }
  end

  def openlanes(*)
    out, err, status = Open3.capture3({ "NO_COLOR" => "1" }, exe, *, chdir: repo_root)
    [out, err, status.exitstatus]
  end

  def top = Dir.children(plans_root).sort

  def under(subfolder) = Dir.children(File.join(plans_root, subfolder)).sort

  before do
    init_repo
    plans { |t| folders.each { |name, files| t.raw("#{name[/\A[\d.]+/]}-🟡 → #{name[/[a-z-]+\z/]}", files:) } }
    commit_all("plans", date: "2026-08-01T10:00:00+00:00")
    folders.each_key do |name|
      repo_git("mv", File.join(plans_root, "#{name[/\A[\d.]+/]}-🟡 → #{name[/[a-z-]+\z/]}"), File.join(plans_root, name))
    end
    commit_all("states", date: "2026-09-20T10:00:00+00:00")
  end

  it "previews every rename, move and rewrite under -n, and changes nothing" do
    out, = openlanes("resync", "dirs", "-n")

    aggregate_failures do
      expect(out).to include(
        "001.00━━⚪━━❯dashes",
        "002.00━━⭐━━❯single",
        "003.00━━⭕━━❯tech-block",
        "004.00━━🛑━━❯product-block",
        "archive/005.00━━✅━━❯[2026-09-20]━━shipped",
        "deferred/006.00━━💤━━❯[2026-09-20]━━parked",
        "abandoned/007.00━━❌━━❯[2026-09-20]━━dropped",
        "008.00━━⏪━━❯backfill",
        "009.00-⚪️ → verified/spec.md"
      )
      expect(repo_git("status", "--porcelain")).to eq("")
    end
  end

  context "when resync dirs has run" do
    before do
      _, err, status = openlanes("resync", "dirs")
      raise err unless status.zero?

      commit_all("migrate")
    end

    it "keeps each moved folder's history" do
      shipped = ".plans/archive/005.00━━✅━━❯[2026-09-20]━━shipped/spec.md"

      expect(repo_git("log", "--follow", "--format=%s", "--", shipped).lines.map(&:strip)).to eq(%w[migrate states plans])
    end

    it "leaves only open plans at the top level, no name with a space, and the checks in the body" do
      open_plans = top - OpenLanes::Plans::Tree::SUBFOLDERS

      aggregate_failures do
        expect(open_plans.size).to eq(5) # 008 had a merged pull request and nothing else: ✅, archived
        expect((open_plans + under("archive") + under("deferred") + under("abandoned")).grep(/\s/)).to be_empty
        expect(File.read(File.join(plans_root, "009.00━━⚪━━❯verified", "spec.md")))
          .to end_with("## How to tell it's working?\n\n- just test\n")
      end
    end

    it "hides plans moved aside from plans, and --all shows them dated" do
      listed, = openlanes("plans")
      everything, = openlanes("plans", "--all")

      aggregate_failures do
        expect(listed).not_to include("Shipped", "Parked", "Dropped")
        expect(everything).to include("Shipped [2026-09-20]", "Parked [2026-09-20]", "Dropped [2026-09-20]")
      end
    end

    it "numbers a new plan above the archived ones" do
      created, = openlanes("create", "next", "thing", "--no-draft", "--no-open")

      expect(File.basename(created.strip)).to eq("010.00━━⚪━━❯next-thing")
    end

    it "shows a lock as 🔑 and in the snapshot, and never renames the locked folder" do
      locked = File.join(plans_root, "001.00━━⚪━━❯dashes")
      OpenLanes::Plans::Lock.write(locked)
      File.write(File.join(locked, "plan.md"), "# Plan\n\n## Units\n") # would justify ⭐
      listed, = openlanes("plans")
      openlanes("resync", "dirs")

      aggregate_failures do
        expect(listed).to include("🔑 Dashes")
        expect(snapshot_plan("001.00")[:locked]).to include(pid: Process.pid, host: Socket.gethostname)
        expect(top).to include("001.00━━⚪━━❯dashes")
      end
    end

    it "has nothing left to do on a second run" do
      out, err, = openlanes("resync", "dirs")

      expect([out, err]).to match(["", include("already named")])
    end
  end

  # @param ordinal [String]
  # @return [Hash] that plan's entry in the live snapshot, read as the page reads it
  def snapshot_plan(ordinal)
    node = OpenLanes::Live::Node.new(id: "3f9a0c7be21d44a8f6031c5d",
      user: "dana",
      host: "studio-mini",
      ip: "10.0.4.12",
      checkout: "~/github/example/openlanes",
      checkout_id: "a1b2c3d4e5f6")
    keys = OpenLanes::Live::Keys.new(repo: "github.com/example/openlanes", node: node.name)
    board = OpenLanes::Engine::Board.new(started_at: 0,
      status: :running,
      plans: [ordinal],
      up: 0,
      down: 0,
      rows: [],
      root: repo_root,
      running: 0,
      live_up: 0,
      live_down: 0)
    snapshot = OpenLanes::Live::Snapshot.new(board:,
      tree: OpenLanes::Plans::Tree.new(dir: plans_root),
      agents: OpenLanes::Agents::Registry.new,
      node:,
      repo: keys.repo,
      project: "example",
      seq: 1,
      claims: OpenLanes::Live::Claims.new(store: OpenLanes::Live.memory_store, keys:))
    JSON.parse(JSON.generate(snapshot.to_h), symbolize_names: true)[:plans].find { it[:ordinal] == ordinal }
  end
end
