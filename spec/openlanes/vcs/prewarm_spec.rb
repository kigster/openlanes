# frozen_string_literal: true

# Real git repositories and real copies in a temp dir. Whether the copy is a
# clone or an ordinary one is the filesystem's business, and nothing here
# depends on which it was, so the examples pass on a disk that cannot clone.
RSpec.describe OpenLanes::Vcs::Prewarm do
  subject(:prewarm) { described_class.new(root: repo) }

  let(:tmp) { File.realpath(Dir.mktmpdir("spb-prewarm")) }
  let(:repo) { File.join(tmp, "project") }
  let(:tree) { File.join(tmp, "project.worktrees", "plan") }

  before do
    FileUtils.mkdir_p(File.join(repo, "web"))
    git("init", "-q", "--initial-branch=main")
    git("config", "user.email", "alan.turing@manchester.edu")
    git("config", "user.name", "Alan Turing")
    File.write(File.join(repo, ".gitignore"), "node_modules\n")
    File.write(File.join(repo, "package-lock.json"), %({"name":"root"}\n))
    File.write(File.join(repo, "web", "package-lock.json"), %({"name":"web"}\n))
    git("add", "-A")
    git("commit", "-qm", "initial")
  end

  after { FileUtils.rm_rf(tmp) }

  def git(*, at: repo) = system("git", "-C", at, *, out: File::NULL, err: File::NULL)

  # An installed tree: a package, and the `.bin` symlink npm leaves to it.
  def install(dir, package: "left-pad")
    modules = File.join(dir, "node_modules")
    FileUtils.mkdir_p(File.join(modules, package, "bin"))
    FileUtils.mkdir_p(File.join(modules, ".bin"))
    File.write(File.join(modules, package, "index.js"), "module.exports = 1\n")
    File.write(File.join(modules, package, "bin", "cli.js"), "#!/usr/bin/env node\n")
    File.chmod(0o755, File.join(modules, package, "bin", "cli.js"))
    File.symlink("../#{package}/bin/cli.js", File.join(modules, ".bin", package))
    modules
  end

  def add_worktree = git("worktree", "add", "-q", "-b", "plan", tree)

  describe "#call" do
    it "gives the worktree every node_modules that sits beside a lockfile" do
      install(repo)
      install(File.join(repo, "web"), package: "vite")
      add_worktree

      outcomes = prewarm.call(tree)

      aggregate_failures do
        expect(outcomes.map(&:kind)).to eq(%i[cloned cloned])
        expect(File.read(File.join(tree, "node_modules", "left-pad", "index.js"))).to eq("module.exports = 1\n")
        expect(File.file?(File.join(tree, "web", "node_modules", "vite", "index.js"))).to be(true)
      end
    end

    it "keeps the .bin links as links, and what they run executable" do
      install(repo)
      add_worktree

      prewarm.call(tree)
      link = File.join(tree, "node_modules", ".bin", "left-pad")

      aggregate_failures do
        expect(File.symlink?(link)).to be(true)
        expect(File.readlink(link)).to eq("../left-pad/bin/cli.js")
        expect(File.executable?(link)).to be(true)
      end
    end

    # The whole case against a symlink: an install in one worktree must not
    # change what another, or the main checkout, runs from.
    it "leaves the main checkout's copy alone when the worktree's changes" do
      install(repo)
      add_worktree
      prewarm.call(tree)

      File.write(File.join(tree, "node_modules", "left-pad", "index.js"), "module.exports = 2\n")
      FileUtils.rm_rf(File.join(tree, "node_modules", ".bin"))

      aggregate_failures do
        expect(File.symlink?(File.join(tree, "node_modules"))).to be(false)
        expect(File.read(File.join(repo, "node_modules", "left-pad", "index.js"))).to eq("module.exports = 1\n")
        expect(File.symlink?(File.join(repo, "node_modules", ".bin", "left-pad"))).to be(true)
      end
    end

    it "leaves the checkout clean, so the clone is never taken for an agent's work" do
      install(repo)
      add_worktree

      prewarm.call(tree)

      expect(`git -C #{tree} status --porcelain`).to eq("")
    end

    it "skips a lockfile that differs from the main checkout's" do
      install(repo)
      install(File.join(repo, "web"))
      add_worktree
      File.write(File.join(tree, "web", "package-lock.json"), %({"name":"web","dependencies":{}}\n))

      outcomes = prewarm.call(tree).to_h { [it.lockfile, it] }

      aggregate_failures do
        expect(outcomes.fetch("package-lock.json")).to be_cloned
        expect(outcomes.fetch("web/package-lock.json").kind).to eq(:skipped)
        expect(outcomes.fetch("web/package-lock.json").reason).to include("differs")
        expect(File.exist?(File.join(tree, "web", "node_modules"))).to be(false)
      end
    end

    it "skips when the main checkout never installed" do
      add_worktree

      expect(prewarm.call(tree).map(&:reason).uniq).to eq(["the main checkout has none"])
    end

    it "never touches a node_modules the worktree already has" do
      install(repo)
      add_worktree
      FileUtils.mkdir_p(File.join(tree, "node_modules"))
      File.write(File.join(tree, "node_modules", "mine"), "kept\n")

      outcome = prewarm.call(tree).find { it.lockfile == "package-lock.json" }

      aggregate_failures do
        expect(outcome.reason).to eq("it is already there")
        expect(Dir.children(File.join(tree, "node_modules"))).to eq(["mine"])
      end
    end

    # Unignored, the clone would make every worktree dirty: never pruned,
    # and one `git add -A` away from a commit of ten thousand files.
    it "skips a node_modules git does not ignore" do
      File.write(File.join(repo, ".gitignore"), "")
      git("commit", "-qam", "stop ignoring")
      install(repo)
      add_worktree

      outcome = prewarm.call(tree).find { it.lockfile == "package-lock.json" }

      aggregate_failures do
        expect(outcome.reason).to eq("git does not ignore it here")
        expect(File.exist?(File.join(tree, "node_modules"))).to be(false)
      end
    end

    it "ignores the lockfiles packages ship inside node_modules" do
      modules = install(repo)
      File.write(File.join(modules, "left-pad", "package-lock.json"), "{}\n")
      add_worktree

      expect(prewarm.call(tree).map(&:lockfile)).to contain_exactly("package-lock.json", "web/package-lock.json")
    end

    it "recognises yarn, pnpm and bun lockfiles too" do
      %w[yarn pnpm bun].zip(%w[yarn.lock pnpm-lock.yaml bun.lock]) do |dir, lockfile|
        FileUtils.mkdir_p(File.join(repo, dir))
        File.write(File.join(repo, dir, lockfile), "lock\n")
        install(File.join(repo, dir))
      end
      git("add", "-A")
      git("commit", "-qm", "more package managers")
      add_worktree

      cloned = prewarm.call(tree).select(&:cloned?).map(&:lockfile)

      expect(cloned).to contain_exactly("yarn/yarn.lock", "pnpm/pnpm-lock.yaml", "bun/bun.lock")
    end

    it "does nothing in a project with no lockfile" do
      git("rm", "-q", "package-lock.json", "web/package-lock.json")
      git("commit", "-qm", "no javascript")
      add_worktree

      expect(prewarm.call(tree)).to eq([])
    end

    it "does nothing when asked to warm the main checkout from itself" do
      install(repo)

      expect(prewarm.call(repo)).to eq([])
    end

    context "when the copy fails" do
      subject(:prewarm) { described_class.new(root: repo, command: %w[false]) }

      it "reports it, raises nothing, and leaves no half-made tree behind" do
        install(repo)
        add_worktree
        logged = []
        tap = OpenLanes::UI.tap_log(->(message, _fields) { logged << message })

        outcome = prewarm.call(tree).find { it.lockfile == "package-lock.json" }
        OpenLanes::UI.untap_log(tap)

        aggregate_failures do
          expect(outcome).to be_failed
          expect(logged.join).to include("node_modules not cloned: false failed")
          expect(Dir.children(tree)).not_to include(a_string_starting_with("node_modules"))
        end
      end
    end

    context "when the copy dies halfway" do
      # Writes part of the tree, then fails: what a full disk does.
      subject(:prewarm) { described_class.new(root: repo, command: [script]) }

      let(:script) do
        File.join(tmp, "half-copy").tap do |path|
          File.write(path, "#!/bin/sh\nmkdir -p \"$2/left-pad\"\nexit 1\n")
          File.chmod(0o755, path)
        end
      end

      it "removes the partial copy, so the next round can try again" do
        install(repo)
        add_worktree

        prewarm.call(tree)

        expect(Dir.children(tree)).not_to include(a_string_starting_with("node_modules"))
      end
    end
  end

  describe ".copy_command" do
    it "clones on macOS and reflinks on Linux, falling back to a copy on both" do
      aggregate_failures do
        expect(described_class.copy_command("darwin25")).to eq(%w[cp -c -a])
        expect(described_class.copy_command("linux-gnu")).to eq(%w[cp --reflink=auto -a])
        expect(described_class.copy_command("freebsd14")).to eq(%w[cp -a])
      end
    end
  end

  describe OpenLanes::Vcs::Prewarm::Outcome do
    it "names the directory, not the lockfile, in the log line" do
      aggregate_failures do
        expect(described_class.new(lockfile: "web/package-lock.json", kind: :cloned, reason: nil).to_s)
          .to eq("web/node_modules cloned from the main checkout")
        expect(described_class.new(lockfile: "yarn.lock", kind: :skipped, reason: "the main checkout has none").to_s)
          .to eq("node_modules not cloned: the main checkout has none")
      end
    end
  end
end
