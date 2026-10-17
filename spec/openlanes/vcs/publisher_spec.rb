# frozen_string_literal: true

RSpec.describe OpenLanes::Vcs::Publisher, :tree do
  subject(:publisher) { described_class.new(root: File.dirname(plans_root), command:, dry_run: false, github:) }

  let(:command) { instance_double(TTY::Command) }
  let(:github) { instance_double(OpenLanes::Vcs::GitHub) }
  let(:result) { instance_double(TTY::Command::Result, out: "https://github.com/example/repo/pull/7\n") }

  let!(:built) do
    plans do |t|
      t.plan "000.00",
        :building,
        "folder-capitalized-not-downcased",
        files: { "spec.md" => spec_body(goal: "Make the thing work."), "plan.md" => "# Plan\n\n## How to test\n\n- open the editor\n" }
    end
  end

  let(:plan) { OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first }
  # A Data instance is frozen, so dirtiness — the thing these examples vary —
  # cannot be stubbed on a real one.
  let(:checkout) do
    instance_double(OpenLanes::Vcs::Worktree::Checkout,
      branch: "kig/000.00-folder-capitalized-not-downcased",
      path:   File.dirname(plans_root),
      dirty?: true)
  end

  before do
    allow(command).to receive(:run).and_return(result)
    allow(github).to receive(:swap_label).and_return(["ready-for-review"])
  end

  describe "#title_for" do
    it "matches the convention: [NNN.MM](A) with the folder title-cased" do
      expect(publisher.title_for(plan)).to eq("[000.00](A) Folder Capitalized Not Downcased")
    end

    it "continues the sequence for a plan that already has pull requests" do
      plans do |t|
        t.plan "001.00", :building, "second-feature", prs: [t.merged(1, "first part")]
      end
      second = OpenLanes::Plans::Tree.new(dir: plans_root).find("001.00")

      expect(publisher.title_for(second)).to start_with("[001.00](B)")
    end

    it "honours a forced letter" do
      expect(publisher.title_for(plan, "C")).to start_with("[000.00](C)")
    end

    # Every part is lettered, including the first: a plan that turns out to need
    # only one pull request still reads like every other, and nothing has to be
    # retitled when a second arrives.
    it "letters even a plan's only pull request" do
      expect(publisher.title_for(plan)).to include("(A)")
    end
  end

  describe "the title the rest of the system has to accept" do
    it "is recognised by resync prs as already prefixed, so it is never doubled" do
      expect(OpenLanes::Lifecycle::Resync::Prs::PREFIXED).to match(publisher.title_for(plan))
    end

    it "resolves back to the plan it came from" do
      match = /\[(\d{3}\.\d{2})\]/.match(publisher.title_for(plan))

      expect(OpenLanes::Plans::Ordinal.parse(match[1])).to eq(plan.feature.ordinal)
    end
  end

  describe "#publish" do
    # Worktrees share refs/remotes, so the tracking ref this push moves would
    # otherwise be blamed on whichever agent is still running next door.
    it "declares its push to the autonomy boundary before making it" do
      seen = []
      allow(OpenLanes::Execution::Boundary).to receive(:sanction) { |*args| seen << [:sanction, *args] }
      allow(command).to receive(:run) do |*argv, **|
        seen << [:push] if argv.first(2) == %w[git push]
        result
      end
      publisher.publish(checkout:, subject: plan)

      expect(seen).to eq([[:sanction, checkout.path, "origin", checkout.branch], [:push]])
    end

    it "commits, pushes the branch, then opens the pull request" do
      publisher.publish(checkout:, subject: plan)

      aggregate_failures do
        expect(command).to have_received(:run).with("git", "add", "-A", hash_including(:chdir))
        expect(command).to have_received(:run)
          .with("git", "push", "-u", "origin", checkout.branch, hash_including(:chdir))
        expect(command).to have_received(:run)
          .with("gh",
            "pr",
            "create",
            "-a",
            "@me",
            "-B",
            "main",
            "-t",
            "[000.00](A) Folder Capitalized Not Downcased",
            "-F",
            anything,
            hash_including(:chdir))
      end
    end

    it "returns the URL gh printed" do
      expect(publisher.publish(checkout:, subject: plan).url).to eq("https://github.com/example/repo/pull/7")
    end

    it "labels the new pull request ready-for-review" do
      publication = publisher.publish(checkout:, subject: plan)

      aggregate_failures do
        expect(github).to have_received(:swap_label)
          .with(number: 7, repo: "example/repo", add: OpenLanes::Plans::ReviewLabel::INITIAL, remove: [])
        expect(publication.label_error).to be_nil
      end
    end

    it "keeps the pull request open when labelling fails, and says why" do
      allow(github).to receive(:swap_label).and_raise(OpenLanes::Error, "could not label #7: HTTP 403")
      publication = publisher.publish(checkout:, subject: plan)

      aggregate_failures do
        expect(publication).to be_published
        expect(publication.label_error).to eq("could not label #7: HTTP 403")
      end
    end

    it "copies the How to test section into the pull request body" do
      body = nil
      allow(command).to receive(:run) do |*argv, **|
        body = File.read(argv[argv.index("-F") + 1]) if argv[0, 3] == %w[gh pr create]
        result
      end
      publisher.publish(checkout:, subject: plan)

      expect(body).to include("## How to test\n\n- open the editor")
    end

    context "when plan.md predates the rename and says How to verify" do
      before { File.write(File.join(plan.feature.path, "plan.md"), "# Plan\n\n## How to verify\n\n- open the editor\n") }

      it "publishes it, its steps under How to test" do
        body = nil
        allow(command).to receive(:run) do |*argv, **|
          body = File.read(argv[argv.index("-F") + 1]) if argv[0, 3] == %w[gh pr create]
          result
        end

        aggregate_failures do
          expect(publisher.publish(checkout:, subject: plan).refusal).to be_nil
          expect(body).to include("## How to test\n\n- open the editor")
        end
      end
    end

    context "when plan.md has no How to test section" do
      before { File.write(File.join(plan.feature.path, "plan.md"), "# Plan\n\n## U1\n") }

      it "refuses to open the pull request" do
        publication = publisher.publish(checkout:, subject: plan)

        aggregate_failures do
          expect(publication.refusal).to include("## How to test")
          expect(command).not_to have_received(:run).with("gh", "pr", "create", any_args)
        end
      end
    end

    # The bracketed prefix is a join key for pull request titles. Repeating it
    # on every commit subject adds nothing and eats the 50 characters.
    it "keeps the prefix out of the commit subject" do
      publisher.publish(checkout:, subject: plan)

      expect(command).to have_received(:run)
        .with("git", "commit", "-m", "Folder Capitalized Not Downcased", hash_including(:chdir))
    end

    context "when the agent changed nothing" do
      let(:checkout) do
        instance_double(OpenLanes::Vcs::Worktree::Checkout,
          branch: "kig/000.00-x",
          path:   File.dirname(plans_root),
          dirty?: false)
      end

      it "refuses rather than opening an empty pull request" do
        publication = publisher.publish(checkout:, subject: plan)

        aggregate_failures do
          expect(publication).not_to be_published
          expect(publication.refusal).to include("unchanged")
        end
      end

      it "runs no git or gh command at all" do
        publisher.publish(checkout:, subject: plan)

        expect(command).not_to have_received(:run)
      end
    end

    # A re-build after 🔴: the branch already carries the pull request the
    # reviewer asked changes of, and a second `gh pr create` on it fails.
    context "when the plan already has an open pull request" do
      let!(:built) do
        plans do |t|
          t.plan "000.00", :rejected, "rebuilt", files: { "spec.md" => spec_body }, prs: [t.open(7, "[000.00](A) Rebuilt")]
        end
      end
      let(:head) { checkout.branch }
      let(:lookup_error) { nil }
      let(:publication) { publisher.publish(checkout:, subject: plan) }

      before do
        lookup = allow(github).to receive(:pull_request).with("7")
        lookup_error ? lookup.and_raise(OpenLanes::Error, lookup_error) : lookup.and_return({ number: 7, branch: head })
        publication
      end

      it "asks GitHub which branch the pull request is built from" do
        expect(github).to have_received(:pull_request).with("7")
      end

      it "commits and pushes to the same branch and opens nothing" do
        aggregate_failures do
          expect(command).to have_received(:run).with("git", "commit", "-m", "Rebuilt", hash_including(:chdir))
          expect(command).to have_received(:run).with("git", "push", "-u", "origin", checkout.branch, hash_including(:chdir))
          expect(command).not_to have_received(:run).with("gh", any_args)
        end
      end

      # The last verdict, typically review-rejected, would otherwise read to
      # the watch as a new rejection and send the plan back to 🔴; a retired M3
      # verdict would sit beside the new label.
      it "resets the review label to ready-for-review, taking off the previous verdict" do
        expect(github).to have_received(:swap_label)
          .with(number: 7,
            repo: "example/repo",
            add: OpenLanes::Plans::ReviewLabel::INITIAL,
            remove: OpenLanes::Plans::ReviewLabel.known)
      end

      it "reports that pull request, marked as updated" do
        expect(publication).to have_attributes(url: "https://github.com/example/repo/pull/7", title: "[000.00](A) Rebuilt", updated: true)
      end

      # An adopted or hand-opened pull request can come from any branch, and
      # pushing the worktree branch would reach no pull request at all.
      context "when that pull request is built from another branch" do
        let(:head) { "someone/hand-made-branch" }

        it "refuses, naming both branches" do
          expect(publication).to have_attributes(
            url:     nil,
            updated: false,
            refusal: a_string_including("publish refused", "someone/hand-made-branch", checkout.branch)
          )
        end

        it "commits and pushes nothing" do
          expect(command).not_to have_received(:run)
        end
      end

      context "when GitHub cannot say which branch it is built from" do
        let(:lookup_error) { "could not read pull request 7: offline" }

        it "refuses with the reason" do
          expect(publication.refusal).to include("publish refused", "offline")
        end

        it "commits and pushes nothing" do
          expect(command).not_to have_received(:run)
        end
      end
    end

    context "on a dry run" do
      subject(:publisher) do
        described_class.new(root: File.dirname(plans_root), command:, dry_run: true, github:)
      end

      it "reports the title it would use and touches nothing" do
        publication = publisher.publish(checkout:, subject: plan)

        aggregate_failures do
          expect(publication.title).to eq("[000.00](A) Folder Capitalized Not Downcased")
          expect(publication).not_to be_published
          expect(command).not_to have_received(:run)
        end
      end
    end

    context "when gh refuses" do
      before do
        allow(command).to receive(:run).with("gh", any_args)
                                       .and_raise(TTY::Command::ExitError.new("gh pr create",
                                         instance_double(TTY::Command::Result,
                                           exit_status: 1,
                                           out:         "",
                                           err:         "a pull request already exists for this branch")))
      end

      it "reports the refusal instead of raising" do
        expect(publisher.publish(checkout:, subject: plan).refusal).to include("already exists")
      end
    end
  end

  # Real git and a bare origin: what is under test is which paths reach the
  # commit, and a stubbed git would only echo back what the stub was told.
  describe "#commit_plan" do
    subject(:publisher) do
      described_class.new(root: repo_root, command: TTY::Command.new(printer: :null), dry_run: false, github:)
    end

    let(:checkout) { instance_double(OpenLanes::Vcs::Worktree::Checkout, branch: "main", path: repo_root, dirty?: true) }
    let(:origin) { "#{repo_root}-origin.git" }
    let(:screenshot) { File.join(plan.feature.path, "verification", "1", "final.png") }

    before do
      init_repo
      repo_git("config", "user.name", "Test Author")
      repo_git("config", "user.email", "test@example.com")
      repo_git("config", "commit.gpgsign", "false")
      commit_all("seed")
      system("git", "init", "-q", "--bare", origin, exception: true)
      repo_git("remote", "add", "origin", origin)
      repo_git("push", "-q", "-u", "origin", "main")
      FileUtils.mkdir_p(File.dirname(screenshot))
      File.binwrite(screenshot, "\x89PNG\r\n\x1a\n")
      allow(OpenLanes::Execution::Boundary).to receive(:sanction)
    end

    after { FileUtils.rm_rf(origin) }

    it "commits the plan folder, pushes it and returns the SHA" do
      sha = publisher.commit_plan(checkout:, plan:, message: "Verify 000.00")

      aggregate_failures do
        expect(sha).to eq(repo_git("rev-parse", "HEAD").strip)
        expect(repo_git("rev-parse", "origin/main").strip).to eq(sha)
        expect(repo_git("show", "--name-only", "--format=", sha)).to include("verification/1/final.png")
        expect(OpenLanes::Execution::Boundary).to have_received(:sanction).with(repo_root, "origin", "main")
      end
    end

    it "refuses a checkout with a change outside the plan folder, and commits nothing" do
      File.write(File.join(repo_root, "app.rb"), "puts :stray\n")
      before = repo_git("rev-parse", "HEAD")

      aggregate_failures do
        expect { publisher.commit_plan(checkout:, plan:, message: "Verify") }
          .to raise_error(OpenLanes::Error, /outside its plan folder: untracked app\.rb/)
        expect(repo_git("rev-parse", "HEAD")).to eq(before)
      end
    end

    it "names untracked leftovers apart from edits, with the hint to ignore them" do
      File.write(File.join(repo_root, "README.md"), "seeded\n")
      repo_git("add", "README.md")
      repo_git("commit", "-q", "-m", "readme", "--", "README.md")
      File.write(File.join(repo_root, "README.md"), "edited\n")
      FileUtils.mkdir_p(File.join(repo_root, "log"))
      File.write(File.join(repo_root, "log", "test.log"), "boot\n")

      expect { publisher.commit_plan(checkout:, plan:, message: "Verify") }
        .to raise_error(OpenLanes::Error,
          "refused to commit #{plan.feature.ordinal}: changes outside its plan folder: edited README.md; " \
          "untracked log/test.log (left by the app or its tests? add them to .gitignore)")
    end

    it "counts the untracked files past the first ten rather than listing every one" do
      FileUtils.mkdir_p(File.join(repo_root, "tmp"))
      12.times { File.write(File.join(repo_root, "tmp", format("cache-%02d", it)), "") }

      expect { publisher.commit_plan(checkout:, plan:, message: "Verify") }
        .to raise_error(OpenLanes::Error, %r{tmp/cache-09 and 2 more \(left by the app})
    end

    it "is not a resubmit, so the review labels are left alone" do
      publisher.commit_plan(checkout:, plan:, message: "Verify")

      expect(github).not_to have_received(:swap_label)
    end

    it "refuses when there is nothing new to commit" do
      FileUtils.rm_rf(File.dirname(screenshot))

      expect { publisher.commit_plan(checkout:, plan:, message: "Verify") }
        .to raise_error(OpenLanes::Error, /nothing to commit/)
    end

    it "changes nothing on a dry run" do
      dry = described_class.new(root: repo_root, command: TTY::Command.new(printer: :null), dry_run: true, github:)

      expect(dry.commit_plan(checkout:, plan:, message: "Verify")).to be_nil
    end
  end
end
