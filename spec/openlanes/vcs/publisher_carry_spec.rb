# frozen_string_literal: true

# The plan folder travels with its pull request: the publisher copies it from
# the main checkout into the plan's worktree before committing. Real git, a
# real worktree, and a real `.plans` tree, since what is being checked is
# which files end up where.
RSpec.describe OpenLanes::Vcs::Publisher, :tree do
  subject(:publisher) { described_class.new(root: repo, command:, dry_run: false, github:) }

  let(:repo) { File.dirname(plans_root) }
  let(:command) { instance_double(TTY::Command) }
  let(:github) { instance_double(OpenLanes::Vcs::GitHub, swap_label: ["ready-for-review"]) }
  let(:worktrees) { Dir.mktmpdir("openlanes-carry") }
  let(:checkout) { OpenLanes::Vcs::Worktree.new(root: repo, dir: worktrees, user: "tester", seeder: nil).checkout_for(plan.feature) }
  let(:carried) { File.join(checkout.path, OpenLanes::PLANS_DIR) }

  # Copies of plan 004 in the worktree. A committed `.plans` brings the other
  # plans along with the branch, which the publisher leaves alone.
  def copies = Dir.children(carried).select { it.start_with?("004.00") }

  def plan = OpenLanes::Plans::Tree.new(dir: plans_root).find("004.00")

  def git(*) = system("git", "-C", repo, *, out: File::NULL, err: File::NULL)

  before do
    plans do |t|
      t.plan "004.00", :planned, "carry", files: { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## U1\n\n## How to test\n\n- run it\n" }
      t.plan "005.00", :new, "other", files: { "spec.md" => spec_body }
    end
    git("init", "-q", "--initial-branch=main")
    git("config", "user.email", "ada@example.com")
    git("config", "user.name", "Ada")
    File.write(File.join(repo, "README.md"), "# repo\n")
    git("add", "README.md")
    git("commit", "-qm", "initial")
  end

  after { FileUtils.rm_rf(worktrees) }

  shared_examples "a plan folder carried into the worktree" do
    it "copies the folder under its current name, and no other plan" do
      publisher.carry_plan(checkout, plan)
      aggregate_failures do
        expect(copies).to eq([plan.feature.dirname])
        expect(Dir.children(carried)).not_to include(a_string_including("other")) unless committed
        expect(File.read(File.join(carried, plan.feature.dirname, "plan.md"))).to eq("# Plan\n\n## U1\n\n## How to test\n\n- run it\n")
      end
    end

    it "replaces the copy after a rename, dropping the old name and files deleted since" do
      publisher.carry_plan(checkout, plan)
      File.write(File.join(plan.feature.path, "blocked.md"), "# Blocked\n")
      publisher.carry_plan(checkout, plan)
      File.delete(File.join(plan.feature.path, "blocked.md"))
      plan.machine.promote!(:building)
      File.write(File.join(plan.feature.path, "state.json.1.2.tmp"), "{")

      publisher.carry_plan(checkout, plan)
      copy = File.join(carried, plan.feature.dirname)
      aggregate_failures do
        expect(copies).to eq([plan.feature.dirname])
        expect(plan.feature.dirname).to include("🟡")
        # state.json is the plan's history (stages, signatures, mailbox) and
        # travels; a half-written temporary does not.
        expect(Dir.children(copy)).to contain_exactly("spec.md", "plan.md", "state.json")
      end
    end

    it "leaves the main checkout's folder as it was" do
      before = Dir.children(plan.feature.path).sort
      publisher.carry_plan(checkout, plan)
      expect(Dir.children(plan.feature.path).sort).to eq(before)
    end
  end

  context "with .plans untracked on main" do
    let(:committed) { false }

    it_behaves_like "a plan folder carried into the worktree"
  end

  context "with .plans committed on main" do
    let(:committed) { true }

    before do
      git("add", OpenLanes::PLANS_DIR)
      git("commit", "-qm", "plans")
    end

    it_behaves_like "a plan folder carried into the worktree"
  end

  it "copies before it commits, so the commit carries the plan" do
    present = nil
    allow(command).to receive(:run) do |*argv, **|
      present = File.directory?(File.join(carried, plan.feature.dirname)) if argv[0, 2] == %w[git add]
      instance_double(TTY::Command::Result, out: "https://github.com/example/repo/pull/9\n")
    end
    File.write(File.join(checkout.path, "app.rb"), "puts 1\n")

    publisher.publish(checkout:, subject: plan)
    expect(present).to be(true)
  end

  it "copies nothing when the checkout is the main checkout itself" do
    main = OpenLanes::Vcs::Worktree::Checkout.new(ordinal: plan.feature.ordinal, branch: "main", path: repo, created: false)
    aggregate_failures do
      expect(publisher.carry_plan(main, plan)).to be_nil
      expect(File.read(File.join(plan.feature.path, "plan.md"))).to eq("# Plan\n\n## U1\n\n## How to test\n\n- run it\n")
    end
  end
end
