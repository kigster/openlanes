# frozen_string_literal: true

require "open3"

# Real repositories, with a bare one on disk standing in for GitHub. Faking
# git here would test the fake, and the whole point is what git itself
# records when something pushes.
RSpec.describe OpenLanes::Execution::Boundary do
  let(:dir) { Dir.mktmpdir("boundary") }
  let(:origin) { File.join(dir, "origin.git") }
  let(:work) { File.join(dir, "work") }
  # Somebody else's clone: a teammate, CI, another machine.
  let(:other) { File.join(dir, "other") }

  after do
    described_class.reset!
    FileUtils.rm_rf(dir)
  end

  def git(dir, *args)
    out, status = Open3.capture2e("git", "-C", dir, *args)
    raise "git #{args.join(" ")} failed: #{out}" unless status.success?

    out.strip
  end

  def clone(path)
    git(dir, "clone", "-q", origin, path)
    git(path, "config", "user.email", "alan.turing@manchester.edu")
    git(path, "config", "user.name", "Alan Turing")
  end

  # A commit that HEAD does not move to, so only the push check can see it.
  def detached_commit(dir) = git(dir, "commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "aside")

  before do
    git(dir, "init", "-q", "--bare", "--initial-branch=main", origin)
    clone(work)
    git(work, "commit", "-q", "--allow-empty", "-m", "initial")
    git(work, "push", "-q", "origin", "HEAD:main")
    clone(other)
  end

  def violation_after
    before = described_class.snapshot(work)
    yield
    before.violation(work)
  end

  it "passes a run that touched nothing" do
    expect(violation_after { nil }).to be_nil
  end

  it "reports a commit, as it always has" do
    expect(violation_after { git(work, "commit", "-q", "--allow-empty", "-m", "sneaky") })
      .to include("agent committed", "HEAD moved")
  end

  describe "a push" do
    it "reports a new branch pushed from the checkout" do
      expect(violation_after { git(work, "push", "-q", "origin", "HEAD:refs/heads/sneaky") })
        .to include("agent pushed (origin/sneaky)", "nothing leaves the machine")
    end

    it "reports an existing branch moved by a push, though HEAD stayed put" do
      expect(violation_after { git(work, "push", "-q", "origin", "#{detached_commit(work)}:refs/heads/main") })
        .to include("agent pushed (origin/main)")
    end

    it "reports a push followed by a fetch of the same branch" do
      violation = violation_after do
        git(work, "push", "-q", "origin", "HEAD:refs/heads/sneaky")
        git(work, "fetch", "-q", "origin")
      end

      expect(violation).to include("origin/sneaky")
    end

    it "passes a push the harness declared first, as the publisher does" do
      violation = violation_after do
        git(work, "branch", "kig/000.00-feature")
        described_class.sanction(work, "origin", "kig/000.00-feature")
        git(work, "push", "-q", "origin", "kig/000.00-feature")
      end

      expect(violation).to be_nil
    end

    it "still reports a push of a branch the harness declared at another commit" do
      git(work, "branch", "kig/000.00-feature")
      described_class.sanction(work, "origin", "kig/000.00-feature")

      expect(violation_after { git(work, "push", "-q", "origin", "#{detached_commit(work)}:refs/heads/kig/000.00-feature") })
        .to include("origin/kig/000.00-feature")
    end
  end

  # An agent may fetch to read what is upstream. That moves tracking refs to
  # what the remote already holds, and nothing leaves the machine.
  describe "a fetch" do
    before do
      git(other, "commit", "-q", "--allow-empty", "-m", "theirs")
      git(other, "push", "-q", "origin", "HEAD:main")
      git(other, "push", "-q", "origin", "HEAD:refs/heads/their-branch")
    end

    it "passes a fetch that moved an existing tracking ref and added a new one" do
      expect(violation_after { git(work, "fetch", "-q", "origin") }).to be_nil
    end

    it "passes a fetch of one branch" do
      expect(violation_after { git(work, "fetch", "-q", "origin", "main") }).to be_nil
    end

    # With reflogs off, a moved ref carries no record of what moved it, and a
    # boundary that guessed "fetch" would wave every push through.
    it "reports a moved ref it cannot explain, when reflogs are switched off" do
      git(work, "config", "core.logAllRefUpdates", "false")

      expect(violation_after { git(work, "fetch", "-q", "origin") }).to include("origin/their-branch")
    end
  end

  it "ignores the symbolic origin/HEAD, which set-head moves without pushing" do
    expect(violation_after { git(work, "remote", "set-head", "origin", "main") }).to be_nil
  end

  it "checks nothing outside a repository" do
    plain = File.join(dir, "plain").tap { |path| Dir.mkdir(path) }
    before = described_class.snapshot(plain)

    expect([before.head, before.remotes, before.violation(plain)]).to eq([nil, {}, nil])
  end

  it "declares nothing for a checkout that has no such branch" do
    described_class.sanction(work, "origin", "no-such-branch")

    expect(described_class.sanctioned?("refs/remotes/origin/no-such-branch", git(work, "rev-parse", "HEAD"))).to be(false)
  end
end
