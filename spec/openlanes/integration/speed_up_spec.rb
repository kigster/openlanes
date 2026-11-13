# frozen_string_literal: true

# Plan 061 end to end, over real git, real worktrees and the repository's own
# agents/*.md. The only stand-ins are the GitHub seam (the fake `gh`, and a
# counting double for the snapshot) and the dependency installer, so the suite
# never reaches the network or runs bundler for real.
RSpec.describe "Speed up openlanes (plan 061)", :fake_gh, :tree do
  let(:repo) { File.dirname(plans_root) }
  let(:origin) { Dir.mktmpdir("openlanes-origin") }
  let(:worktree_dir) { Dir.mktmpdir("openlanes-worktrees") }
  let(:cache) { Dir.mktmpdir("openlanes-deps") }
  let(:installs) { [] }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  # The installer stand-in: `bundle check` never passes, and an install
  # leaves a target behind for the cache to keep.
  let(:installer) do
    lambda do |argv, dir, env|
      next false if argv == %w[bundle check]

      installs << dir
      FileUtils.mkdir_p(env.fetch("BUNDLE_PATH"))
      true
    end
  end
  let(:worktrees) do
    OpenLanes::Vcs::Worktree.new(root: repo,
      dir: worktree_dir,
      user: "tester",
      seeder: nil,
      warmup: OpenLanes::Vcs::Warmup.new(cache:, runner: installer))
  end

  def git(*args, dir: repo) = system("git", "-C", dir, *args, out: File::NULL, err: File::NULL) || raise("git #{args.join(" ")} failed")

  before do
    plans do |t|
      t.plan "061.00", :in_review, "first", files: { "spec.md" => spec_body }, prs: [t.open(1, "First")]
      t.plan "062.00", :building, "second", files: { "spec.md" => spec_body }
    end
    File.write(File.join(repo, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(repo, "Gemfile.lock"), "GEM\n  specs:\n\nBUNDLED WITH\n   2.6.0\n")
    File.write(File.join(repo, ".gitignore"), "/.bundle/\n")
    git("init", "-q", "--initial-branch=main")
    git("config", "user.email", "ada@example.com")
    git("config", "user.name", "Ada")
    git("add", "-A")
    git("commit", "-qm", "initial")
    git("init", "-q", "--bare", dir: origin)
    git("remote", "add", "origin", origin)
    git("push", "-q", "-u", "origin", "main")
    git("fetch", "-q", "origin")
  end

  after { [origin, worktree_dir, cache].each { FileUtils.rm_rf(it) } }

  it "installs dependencies once for two plans' worktrees with one lockfile" do
    paths = %w[061.00 062.00].map { worktrees.checkout_for(tree.reload.find(it).feature).path }

    aggregate_failures do
      expect(paths.uniq.size).to eq(2)
      expect(installs.size).to eq(1)
      expect(paths).to all(satisfy { File.directory?(File.join(it, ".bundle/openlanes-gems")) })
    end
  end

  # Three open pull requests, read by every reader in one tick: GitHub is
  # asked for one snapshot, and never for a single pull request.
  it "answers a tick's reads of three pull requests from one snapshot" do
    rows = [201, 202, 203].to_h do |number|
      [number, { number:, labels: %w[openlanes], checks: [{ "name" => "ci", "bucket" => "pass" }],
                 head: "h#{number}", url: "https://github.com/example/repo/pull/#{number}" }]
    end
    github = instance_double(OpenLanes::Vcs::GitHub)
    allow(github).to receive(:open_pull_snapshot)
      .and_return(OpenLanes::Vcs::PullSnapshot.new(pulls: rows.values, taken_at: Time.now))
    snapshot = OpenLanes::Engine::Steps::Snapshot.new(github:, seconds: 60, clock: -> { 0.0 })
    reads = OpenLanes::Vcs::SnapshotReads.new(github, snapshot:)

    rows.each_key do |number|
      reads.labels(number:)
      reads.checks(number:)
    end

    expect(github).to have_received(:open_pull_snapshot).once
  end

  describe "staged review, with the repository's own reviewers" do
    subject(:reviews) do
      OpenLanes::Engine::Reviews.new(agents:, review:, changes: OpenLanes::Vcs::Changes.new(worktree: worktrees))
    end

    let(:agents) { OpenLanes::Agents::Registry.new }
    let(:review) { OpenLanes::Vcs::Review.new(github: OpenLanes::Vcs::GitHub.new) }
    let(:checkout) { worktrees.checkout_for(tree.reload.find("061.00").feature).path }
    let(:names) { %w[staff-reviewer security-reviewer design-reviewer] }

    def plan = tree.reload.find("061.00")
    def startable = names.select { reviews.due?(plan, agents.find(it)) }

    before do
      edit_gh do |data|
        data["labels"] = OpenLanes::Plans::ReviewLabel::ALL.map(&:name)
        data["prs"] = { "1" => gh_pr(title: "First",
          url: "https://github.com/example/repo/pull/1",
          labels: %w[review-in-progress],
          checks: [{ "name" => "ci", "state" => "SUCCESS", "bucket" => "pass" }]) }
      end
      FileUtils.mkdir_p(File.join(checkout, "lib"))
      File.write(File.join(checkout, "lib/fast.rb"), "# fast\n")
      git("add", "-A", dir: checkout)
      git("commit", "-qm", "touch lib", dir: checkout)
    end

    it "starts staff alone, then security and design on a lib/ diff, and approves when all pass" do
      first = startable
      reviews.vote!(plan, agents.find("staff-reviewer"), 1, "great")
      second = startable
      reviews.vote!(plan, agents.find("security-reviewer"), 1, "passed")
      decision = reviews.decide(plan, agents.find("design-reviewer"), "passed")

      aggregate_failures do
        expect(first).to eq(%w[staff-reviewer])
        expect(second).to include("security-reviewer", "design-reviewer")
        expect([decision.pending?, decision.target]).to eq([false, :approved])
      end
    end
  end
end
