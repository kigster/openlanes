# frozen_string_literal: true

# Real repositories with a real bare `origin`: what a worktree looks like
# after a fetch, a fast-forward or a rebase is git's answer, not ours.
RSpec.describe OpenLanes::Vcs::Refresh, :origin do
  let(:tmp) { Dir.mktmpdir("openlanes-refresh") }
  let(:main) { File.join(tmp, "project") }
  let(:upstream) { publish_with_origin(main, tmp) }
  let(:worktrees) { OpenLanes::Vcs::Worktree.new(root: main, dir: File.join(tmp, "project.worktrees"), user: "tester", seeder: nil) }
  let(:feature) do
    OpenLanes::Plans::Feature.new(ordinal: OpenLanes::Plans::Ordinal.parse("008.01"),
      status: OpenLanes::Plans::STATUS_BY_KEY.fetch(:planned),
      slug: "ewoki-linker",
      dirname: "008.01-⭐️--ewoki-linker",
      path: File.join(main, OpenLanes::PLANS_DIR, "008.01-⭐️--ewoki-linker"))
  end
  let(:checkout) { worktrees.checkout_for(feature) }
  let(:refresh) { described_class.new(path: checkout.path) }

  after { FileUtils.rm_rf(tmp) }

  before { upstream }

  def head(dir = checkout.path) = git!(dir, "rev-parse", "HEAD")
  def origin_main = git!(main, "rev-parse", "refs/remotes/origin/main")

  describe "a new plan branch" do
    # The main checkout's own main is three commits behind origin: the
    # branch used to start there, and the plan built against stale code.
    it "starts from the freshly fetched origin/main, not the main checkout's HEAD" do
      3.times { land(upstream, "lib/landed_#{it}.rb", "# #{it}\n") }

      expect(head).to eq(git!(upstream, "rev-parse", "HEAD"))
    end

    it "starts from the main checkout's HEAD when there is no origin" do
      git!(main, "remote", "remove", "origin")

      expect(head).to eq(git!(main, "rev-parse", "HEAD"))
    end
  end

  # Plan 008.01: no commits of its own, 211 behind. No agent is involved.
  describe "a branch with no commits of its own, behind origin/main" do
    before do
      checkout
      5.times { land(upstream, "lib/landed_#{it}.rb", "# #{it}\n") }
    end

    it "fast-forwards it, so the agent sees what landed" do
      outcome = refresh.call

      aggregate_failures do
        expect(outcome).to have_attributes(kind: :fast_forwarded, commits: 5, base: "origin/main")
        expect(head).to eq(origin_main)
        expect(File).to exist(File.join(checkout.path, "lib/landed_4.rb"))
      end
    end

    it "leaves the autonomy boundary nothing to report for the agent that runs next" do
      refresh.call
      before = OpenLanes::Execution::Boundary.snapshot(checkout.path)
      File.write(File.join(checkout.path, "lib/agent.rb"), "# work\n")

      expect(before.violation(checkout.path)).to be_nil
    end

    it "fast-forwards past uncommitted changes git can carry" do
      File.write(File.join(checkout.path, "notes.txt"), "mine\n")

      expect(refresh.call.kind).to eq(:fast_forwarded)
    end

    it "is refused, touching nothing, when an uncommitted change is in a file upstream changed" do
      land(upstream, "app.rb", "upstream\n")
      File.write(File.join(checkout.path, "app.rb"), "local edit\n")
      was = head

      aggregate_failures do
        expect(refresh.call).to have_attributes(kind: :skipped, reason: a_string_including("fast-forward refused"))
        expect(head).to eq(was)
        expect(File.read(File.join(checkout.path, "app.rb"))).to eq("local edit\n")
      end
    end
  end

  describe "a branch already current" do
    it "says so and does nothing" do
      expect(refresh.call).to have_attributes(kind: :current, target: origin_main)
    end
  end

  describe "a branch with commits of its own" do
    before do
      checkout
      commit_file(checkout.path, "lib/plan.rb", "# the plan's work\n")
    end

    it "rebases it onto origin/main, keeping its commit on top" do
      land(upstream, "lib/other.rb", "# other\n")
      outcome = refresh.call

      aggregate_failures do
        expect(outcome).to have_attributes(kind: :rebased, commits: 1)
        expect(git!(checkout.path, "rev-parse", "HEAD~1")).to eq(origin_main)
        expect(git!(checkout.path, "log", "-1", "--format=%s")).to eq("edit lib/plan.rb")
      end
    end

    it "leaves an uncommitted worktree where it is" do
      land(upstream, "lib/other.rb", "# other\n")
      File.write(File.join(checkout.path, "lib/plan.rb"), "# half written\n")
      was = head

      aggregate_failures do
        expect(refresh.call).to have_attributes(kind: :skipped, reason: "uncommitted changes in the worktree")
        expect(head).to eq(was)
      end
    end

    it "holds off while origin/main still names the commit retries ran out on" do
      land(upstream, "lib/other.rb", "# other\n")
      git!(main, "fetch", "-q", "origin")

      expect(refresh.call(hold: origin_main)).to have_attributes(kind: :pending)
    end
  end

  describe "a rebase that stops on a conflict" do
    let!(:before_rebase) do
      checkout
      commit_file(checkout.path, "app.rb", "one\nTWO from the plan\nthree\n")
    end

    before { land(upstream, "app.rb", "one\ntwo from main\nthree\n") }

    it "is left stopped, naming the conflicted files" do
      outcome = refresh.call

      aggregate_failures do
        expect(outcome).to have_attributes(kind: :conflicted, files: ["app.rb"], target: origin_main)
        expect(outcome).to be_conflicted
        expect(refresh).to be_rebasing
        expect(outcome.summary).to include("stopped on conflicts in app.rb")
      end
    end

    it "is continued by the harness once the resolution is staged" do
      refresh.call
      File.write(File.join(checkout.path, "app.rb"), "one\ntwo from main, TWO from the plan\nthree\n")
      git!(checkout.path, "add", "app.rb")

      aggregate_failures do
        expect(refresh.continue).to have_attributes(kind: :rebased, base: "origin/main")
        expect(refresh).not_to be_rebasing
        expect(git!(checkout.path, "rev-parse", "HEAD~1")).to eq(origin_main)
      end
    end

    it "is not continued while a staged file still holds a marker" do
      refresh.call
      git!(checkout.path, "add", "app.rb")

      aggregate_failures do
        expect(refresh.continue).to have_attributes(kind: :conflicted, files: ["app.rb"])
        expect(refresh).to be_rebasing
      end
    end

    it "is not continued while a path is unmerged" do
      refresh.call

      expect(refresh.continue).to have_attributes(kind: :conflicted, files: ["app.rb"])
    end

    it "skips a commit the resolution left empty, and says which" do
      logged = []
      allow(OpenLanes::UI).to receive(:log) { |message, **| logged << message }
      refresh.call
      git!(checkout.path, "checkout", "--ours", "--", "app.rb")
      git!(checkout.path, "add", "app.rb")

      aggregate_failures do
        expect(refresh.continue.kind).to eq(:rebased)
        expect(head).to eq(origin_main)
        expect(logged.join).to match(%r{rebase dropped \h+ .+: its changes are already on origin/main})
      end
    end

    it "stops again on the next commit that conflicts" do
      git!(checkout.path, "reset", "-q", "--hard", before_rebase)
      commit_file(checkout.path, "app.rb", "one\nTWO again\nthree\nfour\n")
      refresh.call
      File.write(File.join(checkout.path, "app.rb"), "one\ntwo from main\nthree\n")
      git!(checkout.path, "add", "app.rb")

      aggregate_failures do
        expect(refresh.continue).to have_attributes(kind: :conflicted, files: ["app.rb"])
        expect(refresh).to be_rebasing
      end
    end

    it "is aborted with the branch restored exactly" do
      refresh.call
      outcome = refresh.abort!("nobody could resolve it")

      aggregate_failures do
        expect(outcome).to have_attributes(kind: :aborted, base: "origin/main", target: origin_main)
        expect(outcome.summary).to include("aborted, branch restored: nobody could resolve it")
        expect(head).to eq(before_rebase)
        expect(refresh).not_to be_rebasing
      end
    end

    it "is picked up where it stood when found stopped" do
      refresh.call

      expect(described_class.new(path: checkout.path).call).to have_attributes(kind: :conflicted, files: ["app.rb"])
    end

    it "is continued when found stopped with the resolution already staged" do
      refresh.call
      File.write(File.join(checkout.path, "app.rb"), "resolved\n")
      git!(checkout.path, "add", "app.rb")

      expect(described_class.new(path: checkout.path).call.kind).to eq(:rebased)
    end

    it "reports a rebase that cannot continue for want of anything to resolve" do
      refresh.call
      File.write(File.join(checkout.path, "app.rb"), "resolved\n")
      git!(checkout.path, "add", "app.rb")
      # Another git process holding the index: the continue fails, and
      # nothing is unmerged for an agent to fix.
      File.write(File.expand_path(git!(checkout.path, "rev-parse", "--git-path", "index.lock"), checkout.path), "")

      expect(refresh.continue).to have_attributes(kind: :skipped, reason: a_string_including("nothing unmerged"))
    end
  end

  describe "a repository without origin" do
    it "is skipped" do
      checkout
      git!(main, "remote", "remove", "origin")

      expect(refresh.call).to have_attributes(kind: :skipped, reason: "no origin default branch")
    end
  end

  describe ".default_branch" do
    it "reads origin/HEAD" do
      git!(main, "remote", "set-head", "origin", "main")

      expect(described_class.default_branch(main)).to eq("main")
    end

    it "falls back to main when origin/HEAD names nothing" do
      expect(described_class.default_branch(tmp)).to eq("main")
    end
  end

  describe ".fetch" do
    it "logs and works from the last fetch when origin cannot be reached" do
      logged = []
      allow(OpenLanes::UI).to receive(:log) { |message, **| logged << message }
      git!(main, "remote", "set-url", "origin", File.join(tmp, "gone.git"))

      aggregate_failures do
        expect(described_class.fetch(main)).to eq("origin/main")
        expect(logged.join).to include("could not fetch origin main")
      end
    end

    # A credential prompt or a stalled socket used to hold the tick thread,
    # and with it every lane, for as long as git cared to wait.
    it "abandons a fetch that hangs, and works from the last fetch" do
      logged = []
      allow(OpenLanes::UI).to receive(:log) { |message, **| logged << message }
      stub_const("#{described_class}::FETCH_TIMEOUT", 0.5)
      git!(main, "remote", "set-url", "origin", "ssh://hang.invalid/project.git")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("GIT_SSH_COMMAND", "ssh").and_return("sh -c 'sleep 30'")

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      aggregate_failures do
        expect(described_class.fetch(main)).to eq("origin/main")
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 10
        expect(logged.join).to include("git fetch timed out after 0.5s", "could not fetch origin main")
      end
    end

    it "never lets git or ssh stop to ask for credentials" do
      expect(described_class.fetch_env).to include("GIT_TERMINAL_PROMPT" => "0",
        "GIT_SSH_COMMAND" => a_string_ending_with("-o BatchMode=yes"))
    end
  end

  describe OpenLanes::Vcs::Refresh::Outcome do
    it "summarises every kind in one line" do
      kinds = %i[current fast_forwarded rebased aborted pending skipped]
      lines = kinds.map { described_class.new(kind: it, base: "origin/main", commits: 1, reason: "why").summary }

      expect(lines).to eq(["worktree: up to date with origin/main",
                           "worktree: fast-forwarded 1 commit to origin/main",
                           "worktree: rebased onto origin/main (1 new upstream commit)",
                           "worktree: rebase onto origin/main aborted, branch restored: why",
                           "worktree: rebase onto origin/main pending: why",
                           "worktree: not refreshed: why"])
    end

    it "counts only the kinds that leave the branch current as done" do
      expect(%i[current fast_forwarded rebased conflicted skipped].map { described_class.new(kind: it).done? })
        .to eq([true, true, true, false, false])
    end
  end

  describe OpenLanes::Vcs::Worktree do
    it "logs every refresh that did something, under the plan's number" do
      logged = []
      allow(OpenLanes::UI).to receive(:log) { |message, **fields| logged << [message, fields] }
      checkout
      land(upstream, "lib/landed.rb", "# landed\n")
      worktrees.refresh(checkout)

      expect(logged.last).to eq(["worktree: fast-forwarded 1 commit to origin/main", { plan: "008.01" }])
    end
  end
end
