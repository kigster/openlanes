# frozen_string_literal: true

require "tmpdir"

# Two checkouts on two branches used to mint the same plan number, each
# seeing only its own `.plans`. Real repositories throughout: a linked
# worktree, branches that carry plans the checkout does not, a bare origin.
RSpec.describe OpenLanes::Lifecycle::Allocator, :tree do
  subject(:allocator) { described_class.new(dir: plans_root) }

  let(:creator) { OpenLanes::Lifecycle::Creator.new(dir: plans_root) }
  let(:words) { %w[tax rule dsl] }
  let(:scratch) { Dir.mktmpdir("openlanes-allocator") }

  after { FileUtils.rm_rf(scratch) }

  def plan(ordinal, slug, **) = plans { |t| t.plan ordinal, :new, slug, files: { "spec.md" => spec_body }, ** }

  def created(**) = File.basename(creator.create(words:, **).value!)

  before do
    init_repo
    plan "001.00", "initial-spec"
    commit_all("plans")
  end

  context "when outside a git repository" do
    subject(:allocator) { described_class.new(dir: plain) }

    let(:plain) { File.join(scratch, ".plans") }

    it "has no repository, refuses nothing, and reads the tree alone" do
      FileUtils.mkdir_p(File.join(plain, "003.00━━⚪━━❯solo"))

      aggregate_failures do
        expect(allocator.repository).to be_nil
        expect(allocator.refusal).to be_nil
        expect(allocator.taken.map(&:to_s)).to eq(["003.00"])
        expect(allocator.hold { :ran }).to eq(:ran)
      end
    end
  end

  context "when in the primary checkout" do
    it "is not a worktree, and refuses nothing" do
      aggregate_failures do
        expect(allocator.repository.worktree?).to be(false)
        expect(allocator.refusal).to be_nil
      end
    end

    it "skips past a number that lives only on another local branch" do
      repo_git("checkout", "-q", "-b", "kig/three-reviewers")
      plan "024.00", "three-reviewers"
      plan "035.00", "auto-merge", under: "archive", archived_on: Date.new(2026, 10, 1)
      commit_all("more plans")
      repo_git("checkout", "-q", "main")

      aggregate_failures do
        expect(Dir.children(plans_root)).to contain_exactly("001.00━━⚪━━❯initial-spec")
        expect(created).to eq("036.00━━⚪━━❯tax-rule-dsl")
      end
    end

    it "skips past a number that lives only on an origin/* remote-tracking branch" do
      origin = File.join(scratch, "origin.git")
      system("git", "init", "-q", "--bare", origin, out: File::NULL, err: File::NULL)
      repo_git("remote", "add", "origin", origin)
      repo_git("checkout", "-q", "-b", "kig/pushed")
      plan "030.00", "pushed-elsewhere"
      commit_all("pushed plan")
      repo_git("push", "-q", "origin", "kig/pushed")
      repo_git("checkout", "-q", "main")
      repo_git("branch", "-q", "-D", "kig/pushed")

      aggregate_failures do
        expect(repo_git("branch", "--list", "kig/pushed")).to be_empty
        expect(created).to eq("031.00━━⚪━━❯tax-rule-dsl")
      end
    end

    it "takes the next retroactive slot past one another branch holds" do
      plan "002.00", "dev-foundation"
      commit_all("002")
      repo_git("checkout", "-q", "-b", "kig/backfill")
      plan "002.01", "backfill"
      commit_all("002.01")
      repo_git("checkout", "-q", "main")

      expect(created(after: "002")).to start_with("002.02━━")
    end

    it "makes a create wait while another holds the lock, then lets it through" do
      File.open(allocator.repository.lock_path, File::RDWR | File::CREAT) do |lock|
        lock.flock(File::LOCK_EX)
        waiting = Thread.new { creator.create(words:) }

        aggregate_failures do
          expect(waiting.join(0.5)).to be_nil
          expect(Dir.children(plans_root).size).to eq(1)

          lock.flock(File::LOCK_UN)
          expect(File.basename(waiting.value.value!)).to eq("002.00━━⚪━━❯tax-rule-dsl")
        end
      end
    end

    it "keeps the lock in the git directory every worktree shares" do
      expect(allocator.repository.lock_path).to eq(File.join(File.realpath(repo_root), ".git", described_class::LOCK_FILE))
    end

    it "gives two creates running at once two different numbers" do
      results = %w[alpha beta].map { |slug|
        Thread.new { OpenLanes::Lifecycle::Creator.new(dir: plans_root).create(words: [slug]) }
      }.map(&:value)

      expect(results.map { File.basename(it.value!)[0, 6] }).to contain_exactly("002.00", "003.00")
    end
  end

  context "when in a linked worktree" do
    let(:worktree) { File.join(scratch, "wt") }
    let(:worktree_plans) { File.join(worktree, ".plans") }
    let(:refusal) do
      "plans are created only in the primary checkout, #{File.realpath(repo_root)}; this is a worktree of it"
    end

    before { repo_git("worktree", "add", "-q", "-b", "kig/side", worktree) }

    it "refuses to create a plan, naming the primary checkout" do
      result = OpenLanes::Lifecycle::Creator.new(dir: worktree_plans).create(words:)

      aggregate_failures do
        expect(result.failure).to eq(refusal)
        expect(Dir.children(worktree_plans)).to contain_exactly("001.00━━⚪━━❯initial-spec")
      end
    end

    it "refuses a retroactive slot too" do
      result = OpenLanes::Lifecycle::Creator.new(dir: worktree_plans).create(words:, after: "001")

      expect(result.failure).to eq(refusal)
    end

    it "refuses to adopt an orphan pull request, previewing or not" do
      adoption = OpenLanes::Lifecycle::Adoption.new(tree: OpenLanes::Plans::Tree.new(dir: worktree_plans),
        github: instance_double(OpenLanes::Vcs::GitHub),
        root: worktree)
      orphan = { number: 7, title: "Orphan", branch: "x", files: [] }

      aggregate_failures do
        expect { adoption.plan([orphan]) }.to raise_error(described_class::Refused, refusal)
        expect { adoption.call([orphan]) }.to raise_error(described_class::Refused, refusal)
      end
    end

    it "makes resync prs a status-73 refusal when it would adopt" do
      github = instance_double(OpenLanes::Vcs::GitHub)
      allow(github).to receive(:pulls).and_return([{ number: 7, title: "Orphan", branch: "kig/009-ghost", files: [],
                                                     url: "u", state: "Open 🟡", open: true }])

      result = OpenLanes::Lifecycle.retitle_prs(tree: OpenLanes::Plans.tree(worktree_plans),
        github:,
        root: worktree,
        commit: false)

      expect(result.failure).to eq(OpenLanes::Refusal.new(message: refusal, status: 73))
    end

    it "still reads the numbers, for anyone who only asks" do
      expect(described_class.new(dir: worktree_plans).taken.map(&:to_s)).to eq(["001.00"])
    end
  end

  context "when the primary checkout is off its default branch" do
    let(:refusal) do
      "plans are created only on main in the primary checkout; #{File.realpath(repo_root)} is on kig/side"
    end

    before { repo_git("checkout", "-q", "-b", "kig/side") }

    it "refuses to create a plan, naming the branch it is on" do
      result = creator.create(words:)

      aggregate_failures do
        expect(result.failure).to eq(refusal)
        expect(Dir.children(plans_root)).to contain_exactly("001.00━━⚪━━❯initial-spec")
      end
    end

    it "names a detached HEAD as one" do
      repo_git("checkout", "-q", "--detach")

      expect(allocator.refusal).to end_with("is on a detached HEAD")
    end

    it "takes origin's HEAD as the default branch when the clone recorded one" do
      repo_git("update-ref", "refs/remotes/origin/kig/side", "HEAD")
      repo_git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/kig/side")

      aggregate_failures do
        expect(allocator.repository.default_branch).to eq("kig/side")
        expect(allocator.refusal).to be_nil
      end
    end
  end
end
