# frozen_string_literal: true

# Real git repositories in a temp dir. A worktree is a git feature, and a test
# that fakes git tests the fake.
RSpec.describe OpenLanes::Vcs::Worktree do
  subject(:worktrees) { described_class.new(root: repo, dir: worktree_dir, user: "tester", seeder:) }

  # No seeder unless an example installs one: the developer's own
  # setup-worktree must not decide what these examples see.
  let(:seeder) { nil }

  let(:tmp) { Dir.mktmpdir("spb-worktree") }
  let(:repo) { File.join(tmp, "project") }
  let(:worktree_dir) { @worktree_dir }
  let(:feature) do
    OpenLanes::Plans::Feature.new(
      ordinal: OpenLanes::Plans::Ordinal.parse("002.00"),
      status:  OpenLanes::Plans::STATUS_BY_KEY.fetch(:new),
      slug:    "tenancy-households",
      dirname: "002.00-⚪️--tenancy-households",
      path:    File.join(repo, OpenLanes::PLANS_DIR, "002.00-⚪️--tenancy-households")
    )
  end

  around do |example|
    Dir.mktmpdir("spb-worktree") do |tmp|
      @worktree_dir = File.join(tmp, "project.worktrees")
      FileUtils.mkdir_p(File.join(repo, OpenLanes::PLANS_DIR))
      system("git", "-C", repo, "init", "-q", "--initial-branch=main", out: File::NULL, err: File::NULL)
      system("git", "-C", repo, "config", "user.email", "alan.turing@manchester.edu")
      system("git", "-C", repo, "config", "user.name", "Alan Turing")
      File.write(File.join(repo, "README.md"), "# project\n")
      system("git", "-C", repo, "add", "-A", out: File::NULL, err: File::NULL)
      system("git", "-C", repo, "commit", "-qm", "initial", out: File::NULL, err: File::NULL)
      example.run
    end
  end

  describe "#branch_for" do
    # Not cosmetic: this is the first thing `resync prs` reads when deciding
    # which plan a pull request implements, so the number carries itself from
    # here to a merged PR with nobody having to remember it.
    it "puts the plan number in the branch name, where resync prs looks for it" do
      expect(worktrees.branch_for(feature)).to eq("tester/002.00-tenancy-households")
    end

    it "produces a branch the pull-request resolver can parse" do
      match = OpenLanes::Lifecycle::Resync::Prs::BRANCH_PATTERN.match(worktrees.branch_for(feature))

      expect(match && match[1]).to eq("002.00")
    end
  end

  describe "#checkout_for" do
    it "creates a real worktree on its own branch" do
      checkout = worktrees.checkout_for(feature)

      aggregate_failures do
        expect(checkout).to be_created
        expect(File.directory?(checkout.path)).to be(true)
        expect(`git -C #{checkout.path} rev-parse --abbrev-ref HEAD`.strip).to eq("tester/002.00-tenancy-households")
      end
    end

    it "reuses an existing checkout rather than failing on a second round" do
      worktrees.checkout_for(feature)

      expect(worktrees.checkout_for(feature)).not_to be_created
    end

    it "puts worktrees beside the repository, never inside it" do
      checkout = worktrees.checkout_for(feature)

      expect(checkout.path).not_to start_with("#{repo}/")
    end

    # The whole point: two agents on two plans share nothing.
    it "gives two plans genuinely separate checkouts" do
      other = feature.with(ordinal: OpenLanes::Plans::Ordinal.parse("003.00"), slug: "ledger")
      first = worktrees.checkout_for(feature)
      second = worktrees.checkout_for(other)

      File.write(File.join(first.path, "scratch.txt"), "from agent one")

      aggregate_failures do
        expect(second.path).not_to eq(first.path)
        expect(File.exist?(File.join(second.path, "scratch.txt"))).to be(false)
      end
    end
  end

  # `git worktree add` brings tracked files and nothing else, so an agent handed
  # a bare checkout cannot run the suite it was told to keep green. It then
  # reports a broken checkout as a broken plan, which is the expensive failure:
  # the diagnosis points at the code rather than at the tree.
  describe "seeding the files git ignores" do
    before do
      File.write(File.join(repo, ".gitignore"), ".env\nconfig/credentials/*.key\n")
      system("git", "-C", repo, "add", "-A", out: File::NULL, err: File::NULL)
      system("git", "-C", repo, "commit", "-qm", "ignore rules", out: File::NULL, err: File::NULL)

      File.write(File.join(repo, ".env"), "SECRET=from-main\n")
      FileUtils.mkdir_p(File.join(repo, "config", "credentials"))
      File.write(File.join(repo, "config", "credentials", "test.key"), "testkey\n")
    end

    # A stand-in for the user's setup-worktree: copies the two ignored files
    # from the main checkout, never over one already there.
    let(:seeder) do
      path = File.join(File.dirname(repo), "fake-setup-worktree")
      File.write(path, <<~SH)
        #!/bin/sh
        dest="$2"
        src=$(git -C "$dest" worktree list --porcelain | sed -n '1s/^worktree //p')
        for f in .env config/credentials/test.key; do
          if [ -f "$src/$f" ] && [ ! -e "$dest/$f" ]; then mkdir -p "$(dirname "$dest/$f")"; cp "$src/$f" "$dest/$f"; fi
        done
      SH
      FileUtils.chmod(0o755, path)
      path
    end

    it "gives a new checkout the .env git would not" do
      checkout = worktrees.checkout_for(feature)

      expect(File.read(File.join(checkout.path, ".env"))).to eq("SECRET=from-main\n")
    end

    it "gives it the credential key, which is what MissingKeyError is about" do
      checkout = worktrees.checkout_for(feature)

      expect(File.read(File.join(checkout.path, "config/credentials/test.key"))).to eq("testkey\n")
    end

    # Worktrees made before any of this existed are still out there, and the
    # seeder only ever adds a missing file, so repairing them costs one
    # subprocess and no risk.
    it "repairs a checkout that was created before seeding existed" do
      checkout = worktrees.checkout_for(feature)
      FileUtils.rm_f(File.join(checkout.path, ".env"))

      worktrees.checkout_for(feature)

      expect(File.exist?(File.join(checkout.path, ".env"))).to be(true)
    end

    it "leaves an agent's own edit alone rather than restoring the original" do
      checkout = worktrees.checkout_for(feature)
      File.write(File.join(checkout.path, ".env"), "SECRET=edited-by-agent\n")

      worktrees.checkout_for(feature)

      expect(File.read(File.join(checkout.path, ".env"))).to eq("SECRET=edited-by-agent\n")
    end

    # A seeded .env is gitignored, so it must not read as agent output. If it
    # did, `prune` would keep every checkout forever and the loop would grow a
    # worktree per round with nothing in any of them.
    it "does not make an untouched checkout look dirty to prune" do
      checkout = worktrees.checkout_for(feature)

      expect { worktrees.prune }.to change { File.directory?(checkout.path) }.from(true).to(false)
    end
  end

  describe ".seeder" do
    let(:bin) { File.join(File.dirname(repo), "bin") }
    let(:script) { File.join(bin, "setup-worktree") }

    before do
      FileUtils.mkdir_p(bin)
      File.write(script, "#!/bin/sh\n")
      FileUtils.chmod(0o755, script)
    end

    it "takes the environment's override first" do
      other = File.join(File.dirname(repo), "mine")
      FileUtils.cp(script, other)
      expect(described_class.seeder("OPENLANES_SETUP_WORKTREE" => other, "PATH" => bin)).to eq(other)
    end

    it "then finds it on PATH" do
      expect(described_class.seeder("PATH" => "/nonexistent#{File::PATH_SEPARATOR}#{bin}")).to eq(script)
    end

    it "then looks in ~/.claude/bin and ~/.agents/bin" do
      expect(described_class.seeder_candidates("PATH" => "").map { File.dirname(it) })
        .to eq([File.expand_path("~/.claude/bin"), File.expand_path("~/.agents/bin")])
    end

    it "skips a file that is not executable" do
      FileUtils.chmod(0o644, script)
      expect(described_class.seeder_candidates("PATH" => bin)).to include(script)
      expect(described_class.seeder("PATH" => bin)).not_to eq(script)
    end
  end

  describe "#seed when the seeder is unavailable" do
    let(:seeder) { "/nonexistent/setup-worktree" }

    # A plan is not worth abandoning over a seeding step.
    it "does not raise, so one missing script cannot stop the loop" do
      expect { worktrees.checkout_for(feature) }.not_to raise_error
    end

    it "still produces the checkout" do
      expect(File.directory?(worktrees.checkout_for(feature).path)).to be(true)
    end

    # The dashboard owns the terminal while this runs, so the note goes to
    # the progress log and nothing reaches STDERR.
    context "when it notes the missing seeder" do
      subject(:seeded) { worktrees.seed(repo) }

      let(:stderr) { StringIO.new }

      around do |example|
        original = $stderr
        $stderr = stderr
        example.run
      ensure
        $stderr = original
      end

      before do
        allow(OpenLanes::UI).to receive(:log)
        seeded
      end

      it "names every place it looked" do
        expect(OpenLanes::UI).to have_received(:log).with(a_string_including("no setup-worktree found", "$OPENLANES_SETUP_WORKTREE", "~/.claude/bin", "~/.agents/bin"), level: :warn)
      end

      it { expect(stderr.string).to be_empty }
    end

    it "answers false so a caller can tell seeding did not happen" do
      expect(worktrees.seed(repo)).to be(false)
    end
  end

  describe "#seed when the seeder is present" do
    let(:exit_status) { 0 }
    let(:seeder) do
      path = File.join(File.dirname(repo), "setup-worktree")
      File.write(path, "#!/bin/sh\nexit #{exit_status}\n")
      FileUtils.chmod(0o755, path)
      path
    end

    it "answers true when the seeder succeeds, saying nothing" do
      expect(worktrees.seed(repo)).to be(true)
    end

    context "when the seeder runs and fails" do
      let(:stderr) { StringIO.new }
      let(:exit_status) { 1 }

      around do |example|
        original = $stderr
        $stderr = stderr
        example.run
      ensure
        $stderr = original
      end

      before { allow(OpenLanes::UI).to receive(:log) }

      # Never fatal: a plan is not worth abandoning over a seeding step, but
      # a suite dying later on a missing key needs this line to explain it.
      it { expect(worktrees.seed(repo)).to be(false) }

      context "when it has run" do
        before { worktrees.seed(repo) }

        it { expect(OpenLanes::UI).to have_received(:log).with(a_string_including("could not seed"), level: :warn) }
        it { expect(stderr.string).to be_empty }
      end

      it "still hands back a usable checkout" do
        expect(File.directory?(worktrees.checkout_for(feature).path)).to be(true)
      end
    end
  end

  describe "#canonical" do
    # git reports resolved paths and macOS routes temp dirs through symlinks
    # (/var -> /private/var), so prune compares canonical paths — but a path
    # whose directory is already gone cannot be resolved, and raising there
    # would make pruning die on exactly the stale entries it exists to drop.
    it "hands a vanished path back as given rather than raising" do
      gone = File.join(repo, "no-such-dir", "worktree")

      expect(worktrees.canonical(gone)).to eq(gone)
    end
  end

  describe "when git refuses to create the worktree" do
    # A regular file squatting on the worktree's path: not a directory, so the
    # reuse branch does not take it, and `git worktree add` cannot either.
    it "raises a named error instead of returning a checkout that does not exist" do
      FileUtils.mkdir_p(worktree_dir)
      File.write(File.join(worktree_dir, "002.00-tenancy-households"), "in the way")

      expect { worktrees.checkout_for(feature) }.to raise_error(OpenLanes::Error, %r{could not create a worktree for tester/002\.00-tenancy-households})
    end
  end

  describe "a worktree directory deleted by hand" do
    # git keeps the registration, marks it `prunable`, and then refuses to
    # create a new worktree at that path — reporting "already exists" about a
    # directory that does not. Anyone who has ever rm -rf'd a worktree hits it.
    it "is recreated rather than refused" do
      first = worktrees.checkout_for(feature)
      FileUtils.rm_rf(first.path)

      expect { worktrees.checkout_for(feature) }.not_to raise_error
    end

    it "comes back on the same branch" do
      FileUtils.rm_rf(worktrees.checkout_for(feature).path)
      again = worktrees.checkout_for(feature)

      expect(`git -C #{again.path} rev-parse --abbrev-ref HEAD`.strip).to eq("tester/002.00-tenancy-households")
    end
  end

  describe "#retire" do
    def git(dir, *) = system("git", "-C", dir, *, out: File::NULL, err: File::NULL)
    def head(dir) = `git -C #{dir} rev-parse HEAD`.strip
    def branch?(name) = git(repo, "show-ref", "--verify", "--quiet", "refs/heads/#{name}")

    def commit(dir, file, body, message = "edit #{file}")
      File.write(File.join(dir, file), body)
      git(dir, "add", "-A")
      git(dir, "commit", "-qm", message)
      head(dir)
    end

    let(:checkout) { worktrees.checkout_for(feature) }
    let(:branch) { "tester/002.00-tenancy-households" }

    # What GitHub does on a squash merge: one new commit on main holding the
    # branch's files, under a hash the branch never had. main moved on first,
    # so the trees differ and only the files the branch changed can match.
    def squash_merge(files)
      commit(repo, "CHANGELOG.md", "unrelated\n", "someone else's work")
      files.each { |file, body| File.write(File.join(repo, file), body) }
      git(repo, "add", "-A")
      git(repo, "commit", "-qm", "Squashed (#7)")
      head(repo)
    end

    it "removes a checkout whose squash-merged work is on main, and its branch" do
      commit(checkout.path, "household.rb", "class Household; end\n")
      merged = squash_merge("household.rb" => "class Household; end\n")

      retired = worktrees.retire(checkout.path, merge_commit: merged, base: "main")

      aggregate_failures do
        expect(retired).to be_removed
        expect(retired.branch).to eq(branch)
        expect(File.directory?(checkout.path)).to be(false)
        expect(branch?(branch)).to be(false)
        expect(retired.to_s).to start_with("worktree 002.00-tenancy-households removed (#{branch} was ")
      end
    end

    it "removes a checkout whose tip is the merge commit itself" do
      tip = commit(checkout.path, "household.rb", "class Household; end\n")

      expect(worktrees.retire(checkout.path, merge_commit: tip, base: "main")).to be_removed
    end

    it "keeps a checkout with a commit the merge does not hold" do
      commit(checkout.path, "household.rb", "class Household; end\n")
      merged = squash_merge("household.rb" => "class Household; end\n")
      commit(checkout.path, "ledger.rb", "class Ledger; end\n")

      retired = worktrees.retire(checkout.path, merge_commit: merged, base: "main")

      aggregate_failures do
        expect(retired).not_to be_removed
        expect(retired.reason).to eq("its branch has work that is not in #{merged[0, 8]}")
        expect(File.directory?(checkout.path)).to be(true)
        expect(branch?(branch)).to be(true)
        expect(retired.to_s).to eq("worktree 002.00-tenancy-households kept: #{retired.reason}")
      end
    end

    it "keeps a checkout with uncommitted work" do
      tip = commit(checkout.path, "household.rb", "class Household; end\n")
      File.write(File.join(checkout.path, "notes.md"), "half a thought\n")

      expect(worktrees.retire(checkout.path, merge_commit: tip, base: "main").reason).to eq("it has uncommitted changes")
    end

    # A stacked pull request merges into its parent's branch and reports
    # MERGED all the same, while main never sees it.
    it "keeps a checkout whose pull request merged anywhere but main" do
      tip = commit(checkout.path, "household.rb", "class Household; end\n")

      expect(worktrees.retire(checkout.path, merge_commit: tip, base: "tester/001.00-parent").reason)
        .to eq("its pull request merged into tester/001.00-parent, not main")
    end

    it "keeps a checkout somebody holds a lock in" do
      tip = commit(checkout.path, "household.rb", "class Household; end\n")
      held = ->(path) { path == checkout.path ? "luke-backend (fixing a spec)" : nil }

      expect(worktrees.retire(checkout.path, merge_commit: tip, base: "main", held:).reason)
        .to eq("luke-backend (fixing a spec) holds a lock in it")
    end

    it "keeps a checkout when the merge commit cannot be found" do
      commit(checkout.path, "household.rb", "class Household; end\n")

      expect(worktrees.retire(checkout.path, merge_commit: "f" * 40, base: "main").reason)
        .to eq("merge commit ffffffff is not in this repository, even after a fetch")
    end

    it "never touches the main checkout" do
      expect(worktrees.retire(repo, merge_commit: head(repo), base: "main").reason).to eq("not a worktree openlanes manages")
    end

    it "checks everything and removes nothing on a dry run" do
      tip = commit(checkout.path, "household.rb", "class Household; end\n")

      retired = worktrees.retire(checkout.path, merge_commit: tip, base: "main", dry_run: true)

      aggregate_failures do
        expect(retired.reason).to eq("would be removed: landed in #{tip[0, 8]}")
        expect(File.directory?(checkout.path)).to be(true)
        expect(branch?(branch)).to be(true)
      end
    end

    # A locked worktree is one git will not remove without --force, which
    # retire never passes.
    it "says so when git refuses the removal" do
      tip = commit(checkout.path, "household.rb", "class Household; end\n")
      git(repo, "worktree", "lock", checkout.path)

      expect(worktrees.retire(checkout.path, merge_commit: tip, base: "main").reason).to eq("git refused to remove it")
    end
  end

  describe ".main_root" do
    it "finds the main checkout from inside a worktree, where worktrees live beside it" do
      checkout = worktrees.checkout_for(feature)

      expect(File.realpath(described_class.main_root(checkout.path))).to eq(File.realpath(repo))
    end

    it "answers the path itself outside any repository" do
      expect(described_class.main_root(tmp)).to eq(tmp)
    end
  end

  describe "#checkouts_of" do
    # The slug once carried the status, so one plan got a checkout per
    # state it passed through; the ordinal is what they share.
    it "finds every checkout of the plan by its ordinal, and nobody else's" do
      own = worktrees.checkout_for(feature)
      stray = worktrees.checkout_for(feature.with(slug: "002.00━━🟡━━❯tenancy-households"))
      worktrees.checkout_for(feature.with(ordinal: OpenLanes::Plans::Ordinal.parse("003.00"), slug: "ledger"))

      found = worktrees.checkouts_of(feature).map { File.realpath(it) }

      expect(found).to contain_exactly(File.realpath(own.path), File.realpath(stray.path))
    end
  end

  describe "#prune" do
    it "removes checkouts an agent left untouched, since they are pure cost" do
      checkout = worktrees.checkout_for(feature)

      expect { worktrees.prune }.to change { File.directory?(checkout.path) }.from(true).to(false)
    end

    it "keeps a checkout that has changes — that is the output" do
      checkout = worktrees.checkout_for(feature)
      File.write(File.join(checkout.path, "spec.md"), "# written by an agent\n")
      worktrees.prune

      aggregate_failures do
        expect(File.directory?(checkout.path)).to be(true)
        expect(checkout).to be_dirty
      end
    end
  end

  # The reset behind a person's discard (W9): it must take the round's work
  # out of the plan's own checkout and touch nothing else.
  describe "#reset" do
    let(:checkout) { worktrees.checkout_for(feature) }

    def status_of(path) = `git -C #{path} status --porcelain`.strip

    context "with a round's work left in the plan's checkout" do
      before do
        File.write(File.join(checkout.path, "README.md"), "# rewritten by an agent\n")
        File.write(File.join(checkout.path, "half-done.rb"), "class HalfDone; end\n")
        File.write(File.join(repo, "mine.txt"), "a person's own work in the main checkout\n")
      end

      it "puts tracked files back and removes untracked ones, there and only there" do
        aggregate_failures do
          expect(worktrees.reset(feature)).to be(true)
          expect(status_of(checkout.path)).to eq("")
          expect(File.read(File.join(checkout.path, "README.md"))).to eq("# project\n")
          expect(File.read(File.join(repo, "mine.txt"))).to include("own work")
        end
      end
    end

    it "keeps files git ignores, which the seeder put there" do
      File.write(File.join(checkout.path, ".gitignore"), ".env\n")
      system("git", "-C", checkout.path, "add", ".gitignore", out: File::NULL, err: File::NULL)
      system("git", "-C", checkout.path, "commit", "-qm", "ignore", out: File::NULL, err: File::NULL)
      File.write(File.join(checkout.path, ".env"), "SECRET=1\n")
      worktrees.reset(feature)
      expect(File.exist?(File.join(checkout.path, ".env"))).to be(true)
    end

    it "has nothing to do for a plan with no checkout" do
      expect(worktrees.reset(feature)).to be(false)
    end

    it "refuses a directory that is not one of its worktrees" do
      FileUtils.mkdir_p(worktrees.path_for(feature))
      expect { worktrees.reset(feature) }.to raise_error(OpenLanes::Error, /not a worktree openlanes made/)
    end

    context "when the path is the main checkout" do
      let(:main) { described_class.new(root: repo, dir: File.dirname(repo), user: "tester") }

      before { allow(main).to receive(:path_for).and_return(repo) }

      it "refuses it, even where a worktree would sit" do
        expect { main.reset(feature) }.to raise_error(OpenLanes::Error, /not a worktree openlanes made/)
      end
    end

    context "when git refuses" do
      let(:refusing) { described_class.new(root: repo, dir: worktree_dir, user: "tester") }

      before do
        checkout
        allow(refusing).to receive(:system).and_call_original
        allow(refusing).to receive(:system).with("git", "-C", checkout.path, "reset", "--hard", "--quiet", any_args).and_return(false)
      end

      it "says so" do
        expect { refusing.reset(feature) }.to raise_error(OpenLanes::Error, "git reset failed in #{checkout.path}")
      end
    end
  end
end
