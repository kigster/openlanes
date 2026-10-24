# frozen_string_literal: true

# Real git repositories in a temp dir: whether a checkout is a linked
# worktree is a fact about git's own layout, and a fake would only agree
# with itself.
RSpec.describe OpenLanes::Vcs::Mainline do
  def git(dir, *) = system("git", "-C", dir, *, out: File::NULL, err: File::NULL)

  def commit(dir, file, text)
    File.write(File.join(dir, file), text)
    git(dir, "add", "-A")
    git(dir, "commit", "-qm", "edit #{file}")
  end

  def clone_as(dir)
    system("git", "clone", "-q", upstream, dir, out: File::NULL, err: File::NULL)
    git(dir, "config", "user.email", "dev@example.test")
    git(dir, "config", "user.name", "Example Dev")
  end

  let(:tmp) { File.realpath(Dir.mktmpdir("mainline")) }
  let(:repo) { File.join(tmp, "project") }
  let(:upstream) { File.join(tmp, "origin.git") }

  after { FileUtils.rm_rf(tmp) }

  before do
    FileUtils.mkdir_p(repo)
    git(repo, "init", "-q", "--initial-branch=main")
    git(repo, "config", "user.email", "dev@example.test")
    git(repo, "config", "user.name", "Example Dev")
    commit(repo, "README.md", "# project\n")
  end

  it "passes in the primary checkout on main" do
    mainline = described_class.new(root: repo)

    expect(mainline).to be_primary
    expect(mainline).to be_on_branch
    expect(mainline).to be_mainline
    expect(mainline.warnings).to be_empty
  end

  it "warns inside a linked worktree, naming the worktree guard" do
    linked = File.join(tmp, "linked")
    git(repo, "worktree", "add", "-q", "-b", "feature", linked)

    mainline = described_class.new(root: linked)

    expect(mainline).not_to be_mainline
    expect(mainline.warnings).to include(a_string_including("linked worktree"))
  end

  it "warns on a branch other than main, naming the branch guard" do
    git(repo, "checkout", "-q", "-b", "feature")

    expect(described_class.new(root: repo).warnings).to contain_exactly(a_string_including("on branch feature, not main"))
  end

  it "says a detached HEAD is not main" do
    git(repo, "checkout", "-q", "--detach")

    expect(described_class.new(root: repo).warnings).to contain_exactly(a_string_including("(detached HEAD)"))
  end

  it "skips the pull, with a note, when main has no upstream" do
    mainline = described_class.new(root: repo)

    expect(mainline.pull).to be(true)
    expect(mainline.note).to include("no upstream")
  end

  context "with a local bare upstream" do
    let(:local) { File.join(tmp, "local") }
    let(:other) { File.join(tmp, "other") }

    before do
      system("git", "clone", "-q", "--bare", repo, upstream, out: File::NULL, err: File::NULL)
      clone_as(local)
      clone_as(other)
      commit(other, "NEWS.md", "upstream moved\n")
      git(other, "push", "-q", "origin", "main")
    end

    it "fast-forwards main" do
      mainline = described_class.new(root: local)

      expect(mainline.pull).to be(true)
      expect(File).to exist(File.join(local, "NEWS.md"))
      expect(mainline.note).to include("pulled origin/main")
    end

    it "tells the user to commit first when a pull would overwrite local edits" do
      File.write(File.join(local, "NEWS.md"), "an uncommitted edit\n")
      git(local, "add", "NEWS.md")
      mainline = described_class.new(root: local)

      expect(mainline.pull).to be(false)
      expect(mainline.note).to include("git pull --ff-only failed", "commit the spec.md edits from the last link first")
    end

    it "never waits on a credential prompt" do
      allow(Open3).to receive(:capture3).and_call_original
      described_class.new(root: local).pull

      expect(Open3).to have_received(:capture3).with({ "GIT_TERMINAL_PROMPT" => "0" }, "git", "-C", local, "pull", "--ff-only", "--quiet")
    end

    it "reads the mainline branch from origin/HEAD" do
      git(local, "checkout", "-q", "-b", "trunk")
      git(local, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk")
      git(local, "update-ref", "refs/remotes/origin/trunk", "HEAD")

      expect(described_class.new(root: local).branch).to eq("trunk")
    end

    it "reports a diverged pull as a failure" do
      commit(local, "LOCAL.md", "only here\n")
      mainline = described_class.new(root: local)

      expect(mainline.pull).to be(false)
      expect(mainline.note).to include("git pull --ff-only failed")
    end
  end

  it "says a directory outside git is not a checkout, rather than a linked worktree" do
    outside = File.join(tmp, "outside")
    FileUtils.mkdir_p(outside)

    expect(described_class.new(root: outside).warnings).to contain_exactly(a_string_including("is not a git checkout"))
  end

  it "falls back to main when origin/HEAD is unset" do
    expect(described_class.new(root: repo).branch).to eq("main")
  end

  it "is reached through the Vcs facade" do
    expect(OpenLanes::Vcs.mainline(root: repo)).to be_a(described_class)
  end
end
