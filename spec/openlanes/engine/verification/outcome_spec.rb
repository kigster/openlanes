# frozen_string_literal: true

require "erb"

# Real git with a bare origin, a real `.plans` tree and the real GitHub seam,
# answered by the fake `gh`: what is under test is the order things reach
# GitHub and what lands in the branch, which a stubbed seam would only echo.
RSpec.describe OpenLanes::Engine::Verification::Outcome, :fake_gh, :tree do
  subject(:outcome) do
    described_class.new(root: repo_root,
      publisher: OpenLanes::Vcs::Publisher.new(root: repo_root, dry_run: false),
      github: OpenLanes::Vcs::GitHub.new,
      outcomes: OpenLanes::Engine::PrOutcomes.new(tree_dir: plans_root, agents:),
      agents:,
      review:,
      coverage_gate: gate,
      max_rejections: 2,
      arbitration:,
      screenshots: ->(dir) { OpenLanes::Engine::Verification::Screenshots.new(dir:, which: ->(_) { false }) },
      clock: -> { now })
  end

  let(:now) { Time.now }
  let(:review) { OpenLanes::Vcs::Review.new(github: OpenLanes::Vcs::GitHub.new) }

  let(:agents) { OpenLanes::Agents::Registry.new }
  let(:arbitration) { instance_double(OpenLanes::Engine::Arbitration, call: nil) }
  let(:passing) { OpenLanes::Engine::CoverageGate::Verdict.new(passed: true, reason: "coverage 97.00% meets the 95% minimum (simplecov: x)") }
  let(:gate) { instance_double(OpenLanes::Engine::CoverageGate, call: passing) }
  let(:origin) { "#{repo_root}-origin.git" }
  let(:fixture_png) { File.expand_path("../../../fixtures/verification/step.png", __dir__) }
  let(:checkout) { instance_double(OpenLanes::Vcs::Worktree::Checkout, branch: "main", path: repo_root, dirty?: false) }
  let(:plan_md) { "# Plan\n\n## How to test\n\n1. Open the board.\n2. Click New game.\n" }

  def plan = OpenLanes::Plans::Tree.new(dir: plans_root).find("014.00")
  def pr = plan.pull_requests.last
  def round(number = 1) = OpenLanes::Engine::Verification::Round.new(plan_dir: plan.feature.path, number:)
  def origin_files = repo_git("ls-tree", "-r", "-z", "--name-only", "origin/main").split("\0")
  def labels = gh.dig("prs", "1", "labels")
  def comments = gh.dig("prs", "1", "comments").map { it["body"] }
  def mail_to = OpenLanes::Plans::Mailbox.new(dir: plan.feature.path).messages.map(&:to)

  def chewie_left(verdict, step: nil)
    dir = round.make!.dir
    %w[step-01.png step-02.png final.png].each { FileUtils.cp(fixture_png, File.join(dir, it)) }
    File.write(File.join(dir, "app.md"), "# The app\n\nport 11100\n")
    failing = "\n## Failing step\n\n- Step: #{step}\n- What: Click New game\n- Expected: a grid\n- Seen: a 500 page\n" if step
    File.write(File.join(dir, "report.md"), "# Verification, round 1\n\nVerdict: #{verdict}\n#{failing}")
  end

  before do
    plans do |t|
      t.plan "014.00",
        :verifying,
        "chewie-verifier",
        files: { "spec.md" => spec_body, "plan.md" => plan_md },
        prs:   [t.open(1, "Chewie verifier")]
    end
    init_repo
    repo_git("config", "user.name", "Test Author")
    repo_git("config", "user.email", "test@example.com")
    repo_git("config", "commit.gpgsign", "false")
    commit_all("seed")
    system("git", "init", "-q", "--bare", origin, exception: true)
    repo_git("remote", "add", "origin", origin)
    repo_git("push", "-q", "-u", "origin", "main")
    allow(OpenLanes::Execution::Boundary).to receive(:sanction)
    edit_gh do |state|
      state["labels"] = %w[review-approved]
      state["prs"] = { "1" => gh_pr(title: "Chewie verifier", url: "https://github.com/example/repo/pull/1", labels: %w[review-approved]) }
    end
  end

  after { FileUtils.rm_rf(origin) }

  describe "#reject" do
    before { chewie_left("rejected", step: 2) }

    it "pushes the failing step, comments with it, then labels, then sends the plan to 🔴" do
      result = outcome.reject(checkout:, plan:, pull: pr, round:)
      verbs = gh_calls.map { it.take(2) }

      aggregate_failures do
        expect(result).to have_attributes(kind: :rejected, to: :rejected)
        expect(verbs.index(%w[pr comment])).to be < verbs.index(%w[pr edit])
        expect(labels).to eq(%w[review-rejected])
        expect(plan.status.key).to eq(:rejected)
        expect(mail_to).to include("luke-backend", "rey-frontend")
      end
    end

    it "keeps only the failing step and final.png, and none of the engine's own note" do
      outcome.reject(checkout:, plan:, pull: pr, round:)
      pushed = origin_files.grep(%r{/verification/1/}).map { File.basename(it) }

      expect(pushed).to contain_exactly("step-02.png", "final.png", "report.md")
    end

    it "publishes no image that is not PNG, and still prunes the step screenshots" do
      FileUtils.cp(fixture_png, File.join(round.dir, "step-03.webp"))
      allow(OpenLanes::UI).to receive(:log)
      outcome.reject(checkout:, plan:, pull: pr, round:)
      pushed = origin_files.grep(%r{/verification/1/}).map { File.basename(it) }

      aggregate_failures do
        expect(pushed).to contain_exactly("step-02.png", "final.png", "report.md")
        expect(OpenLanes::UI).to have_received(:log).with(a_string_including("not PNG", "deleted step-03.webp rather than publish them"), level: :warn)
      end
    end

    it "names the step, what was expected and what was seen, and links the PNG by SHA, every byte escaped" do
      dirname = plan.feature.dirname
      outcome.reject(checkout:, plan:, pull: pr, round:)
      sha = repo_git("rev-parse", "origin/main").strip
      encoded = ERB::Util.url_encode(dirname)

      aggregate_failures do
        expect(encoded).to include("%F0%9F%A7%AA")
        expect(comments.first).to include("**Step 2:** Click New game", "**Expected:** a grid", "**Seen:** a 500 page")
        expect(comments.first).to include("(https://github.com/example/repo/blob/#{sha}/.plans/#{encoded}/verification/1/step-02.png?raw=true)")
        expect(comments.first.scan(/\(https[^)]*\)/).join).to be_ascii_only
      end
    end

    it "mails the comment itself to the builders" do
      outcome.reject(checkout:, plan:, pull: pr, round:)

      body = OpenLanes::Plans::Mailbox.new(dir: plan.feature.path).messages.find { it.to == "luke-backend" }.body
      expect(body).to include("**Seen:** a 500 page")
    end

    it "counts the rejection against the cap, hansolo's included, and calls the arbitrator at it" do
      OpenLanes::Plans::PlanState.for(plan.feature.path)
                                 .sign!(agent: "hansolo-reviewer", round: 1, status: "Completed", note: "rejected 1/2")
      OpenLanes::Plans::PlanState.for(plan.feature.path)
                                 .sign!(agent: "chewie-verifier", round: 1, status: "Completed", note: "rejected")

      result = outcome.reject(checkout:, plan:, pull: pr, round:)

      aggregate_failures do
        expect(result.note).to include("rejected 2 of 2")
        expect(arbitration).to have_received(:call).with(plan: anything, count: 2, max: 2)
      end
    end
  end

  describe "#reject with a reason chewie could not give" do
    let(:failed) do
      OpenLanes::Engine::Verification::AppSession::Failed.new(process: "web",
        reason: "web exited with status 3 before it was ready",
        tail: (1..20).map { "line #{it}" })
    end

    it "writes the report for it, signs for chewie, and comments with the app's last lines" do
      result = outcome.reject(checkout:, plan:, pull: pr, round:, why: failed.to_markdown)
      report = File.read(File.join(OpenLanes::Plans::Tree.new(dir: plans_root).find("014.00").feature.path, "verification/1/report.md"))

      aggregate_failures do
        expect(result.kind).to eq(:rejected)
        expect(comments.first).to include("the app does not start: web exited with status 3", "line 1\n", "line 20\n")
        expect(report).to include("Verdict: rejected", "chewie-verifier could not say so")
        expect(outcome.rejections(plan)).to eq(1)
        expect(origin_files.grep(%r{verification/1/report\.md})).not_to be_empty
      end
    end
  end

  describe "#rejections" do
    def sign(agent, note) = OpenLanes::Plans::PlanState.for(plan.feature.path).sign!(agent:, round: 1, status: "Completed", note:)

    it "counts only notes that start with the word, never one that merely mentions it" do
      sign("hansolo-reviewer", "rejected 1/2")
      sign("chewie-verifier", "rejected: CI is red on PR #1; signed by harness")
      sign("hansolo-reviewer", "approved, nothing to reject")
      sign("chewie-verifier", "verified; the rejected alternative is gone")
      sign("chewie-verifier", "sent back: Coverage is not declared yet; signed by harness")

      expect(outcome.rejections(plan)).to eq(2)
    end
  end

  describe "#send_back_for_quality (R4, under high)" do
    it "signs a counted rejection, mails the builders, and moves the plan to 🔴 without touching the labels" do
      result = outcome.send_back_for_quality(plan:, pull: pr)

      aggregate_failures do
        expect(result).to have_attributes(kind: :rejected, to: :rejected)
        expect(result.note).to include("rejected 1 of 2", "labels left as hansolo set them")
        expect(outcome.rejections(plan)).to eq(1)
        expect(plan.status.key).to eq(:rejected)
        expect(mail_to).to include("luke-backend", "rey-frontend")
        expect(labels).to eq(%w[review-approved])
        expect(arbitration).not_to have_received(:call)
      end
    end

    it "reaches the arbitrator at the cap, so a PR labelled ok-not-perfect round after round cannot loop for ever" do
      OpenLanes::Plans::PlanState.for(plan.feature.path)
                                 .sign!(agent: "chewie-verifier",
                                   round: 1,
                                   status: "Completed",
                                   note: "rejected: PR #1 is labelled review-ok-not-perfect, an earlier round; signed by harness")

      result = outcome.send_back_for_quality(plan:, pull: pr)

      aggregate_failures do
        expect(result.note).to include("rejected 2 of 2")
        expect(arbitration).to have_received(:call).with(plan: anything, count: 2, max: 2)
      end
    end
  end

  describe "#pass and #settle" do
    before { chewie_left("verified") }

    it "pushes final.png alone, and leaves the plan at 🧪" do
      result = outcome.pass(checkout:, plan:, pull: pr, round:)

      aggregate_failures do
        expect(result).to have_attributes(kind: :committed, to: nil)
        expect(result.note).to include("final.png pushed in", "waiting on CI")
        expect(origin_files.grep(%r{/verification/1/}).map { File.basename(it) }).to contain_exactly("final.png", "report.md")
        expect(plan.status.key).to eq(:verifying)
        expect(labels).to eq(%w[review-approved])
      end
    end

    it "sends the round back, uncounted and saying so, when final.png cannot be committed" do
      File.write(File.join(repo_root, "app.rb"), "puts :stray\n")
      result = outcome.pass(checkout:, plan:, pull: pr, round:)

      aggregate_failures do
        expect(result).to have_attributes(kind: :rejected, to: :rejected)
        expect(result.note).to start_with("verified PR #1 but NOT published (refused to commit 014.00: changes outside its plan folder")
        expect(result.note).to include("not counted (0 of 2)")
        expect(comments.first).to include("final.png never reached the pull request, so it carries no evidence")
        expect(labels).to eq(%w[review-rejected])
        expect(outcome.rejections(plan)).to eq(0)
        expect(OpenLanes::Engine::Verification.latest(plan.feature.path).report.verdict).to eq(:rejected)
      end
    end

    it "sends the round back, saying the commit is local, when the push fails" do
      repo_git("remote", "set-url", "origin", "#{repo_root}-nowhere.git")
      result = outcome.pass(checkout:, plan:, pull: pr, round:)

      aggregate_failures do
        expect(result).to have_attributes(kind: :rejected, to: :rejected)
        expect(result.note).to match(/\Averified PR #1 but NOT published \(committed \h{7} locally, but the push failed: /)
        expect(gate).not_to have_received(:call)
      end
    end

    it "waits while CI is pending, then labels ready-to-merge once it is green and the gate passes" do
      outcome.pass(checkout:, plan:, pull: pr, round:)
      edit_gh { it["prs"]["1"]["checks"] = [{ "name" => "ci", "state" => "PENDING", "bucket" => "pending" }] }
      waiting = outcome.settle(checkout:, plan:, pull: pr, round:)
      edit_gh { it["prs"]["1"]["checks"] = [{ "name" => "ci", "state" => "SUCCESS", "bucket" => "pass" }] }
      ready = outcome.settle(checkout:, plan:, pull: pr, round:)

      aggregate_failures do
        expect(waiting).to have_attributes(kind: :waiting, note: "🧪 waiting on CI for PR #1")
        expect(ready.kind).to eq(:ready)
        expect(labels).to eq(%w[ready-to-merge])
        expect(gh_calls.map { it.take(2) }).not_to include(%w[pr merge])
        expect(plan.status.key).to eq(:verifying)
      end
    end

    context "when the verification commit has no checks yet" do
      it "waits for CI to register rather than taking none for green" do
        outcome.pass(checkout:, plan:, pull: pr, round:)

        aggregate_failures do
          expect(outcome.settle(checkout:, plan:, pull: pr, round:))
            .to have_attributes(kind: :waiting, note: "🧪 no checks yet on PR #1; waiting for CI to start")
          expect(gate).not_to have_received(:call)
          expect(labels).to eq(%w[review-approved])
        end
      end

      context "when the grace period is over" do
        let(:now) { Time.now + described_class::NO_CHECKS_GRACE + 1 }

        it "takes none at its word, as a project with no CI, and labels ready-to-merge" do
          outcome.pass(checkout:, plan:, pull: pr, round:)

          expect(outcome.settle(checkout:, plan:, pull: pr, round:).kind).to eq(:ready)
          expect(labels).to eq(%w[ready-to-merge])
        end
      end
    end

    context "when ready-to-merge is refused after the gate passed" do
      let(:review) { instance_double(OpenLanes::Vcs::Review) }

      def review_result(refused)
        OpenLanes::Vcs::Review::Result.new(pr: 1,
          from: [],
          to: "ready-to-merge",
          ci: refused ? :pending : :green,
          refused:,
          reason: refused ? "CI pending" : nil,
          dry_run: false)
      end

      before do
        allow(review).to receive(:call).and_return(review_result(true), review_result(true), review_result(false))
        edit_gh { it["prs"]["1"]["checks"] = [{ "name" => "ci", "state" => "SUCCESS", "bucket" => "pass" }] }
        outcome.pass(checkout:, plan:, pull: pr, round:)
      end

      it "runs the coverage gate once for the commit, however often it is asked" do
        kinds = Array.new(3) { outcome.settle(checkout:, plan:, pull: pr, round:).kind }

        aggregate_failures do
          expect(kinds).to eq(%i[waiting waiting ready])
          expect(gate).to have_received(:call).once
        end
      end

      it "measures a new commit on the branch afresh" do
        outcome.settle(checkout:, plan:, pull: pr, round:)
        File.write(File.join(repo_root, "fix.rb"), "puts :fixed\n")
        commit_all("a fix")
        outcome.settle(checkout:, plan:, pull: pr, round:)

        expect(gate).to have_received(:call).twice
      end
    end

    it "does nothing more once the pull request is ready-to-merge" do
      edit_gh { it["prs"]["1"]["labels"] = %w[ready-to-merge] }

      expect(outcome.settle(checkout:, plan:, pull: pr, round:).kind).to eq(:ready)
      expect(gate).not_to have_received(:call)
    end

    it "rejects with the gate's message when it withholds" do
      withheld = OpenLanes::Engine::CoverageGate::Verdict.new(passed: false,
        reason: "coverage 80.00% is below the 95% minimum",
        output: ["Finished in 1s", "COVERAGE 80%"])
      allow(gate).to receive(:call).and_return(withheld)
      edit_gh { it["prs"]["1"]["checks"] = [{ "name" => "ci", "state" => "SUCCESS", "bucket" => "pass" }] }

      result = outcome.settle(checkout:, plan:, pull: pr, round:)

      aggregate_failures do
        expect(result).to have_attributes(kind: :rejected, to: :rejected)
        expect(comments.first).to include("coverage 80.00% is below the 95% minimum", "COVERAGE 80%")
        expect(labels).to eq(%w[review-rejected])
      end
    end

    context "when the branch's .openlanes.yml has no coverage: section" do
      let(:unconfigured) do
        OpenLanes::Engine::CoverageGate::Verdict.new(passed: false,
          unconfigured: true,
          reason: ".openlanes.yml in /x has no coverage: section, so nothing was measured")
      end

      before do
        allow(gate).to receive(:call).and_return(unconfigured)
        edit_gh { it["prs"]["1"]["checks"] = [{ "name" => "ci", "state" => "SUCCESS", "bucket" => "pass" }] }
      end

      it "sends the pull request back to luke with the section to write, in both shapes" do
        result = outcome.settle(checkout:, plan:, pull: pr, round:)
        mail = OpenLanes::Plans::Mailbox.new(dir: plan.feature.path).messages.find { it.to == "luke-backend" }

        aggregate_failures do
          expect(result).to have_attributes(kind: :rejected, to: :rejected)
          expect(result.note).to include("sent back PR #1, sent back for setup, not counted (0 of 2)")
          expect(comments.first).to include("chewie-verifier: sent back for setup",
            "Add a `coverage:` section to `.openlanes.yml`",
            "report_command:",
            "format: lcov",
            "does not count against `merge.max_rejections`")
          expect(mail.body).to include("Add a `coverage:` section to `.openlanes.yml` for this stack")
          expect(labels).to eq(%w[review-rejected])
          expect(OpenLanes::Engine::Verification.latest(plan.feature.path).report.verdict).to eq(:rejected)
        end
      end

      it "does not count against merge.max_rejections, nor call the arbitrator at the cap" do
        OpenLanes::Plans::PlanState.for(plan.feature.path)
                                   .sign!(agent: "hansolo-reviewer", round: 1, status: "Completed", note: "rejected 1/2")
        OpenLanes::Plans::PlanState.for(plan.feature.path)
                                   .sign!(agent: "chewie-verifier", round: 1, status: "Completed", note: "rejected")

        result = outcome.settle(checkout:, plan:, pull: pr, round:)

        aggregate_failures do
          expect(outcome.rejections(plan)).to eq(2)
          expect(result.note).to include("not counted (2 of 2)")
          expect(arbitration).not_to have_received(:call)
        end
      end
    end

    it "rejects when CI turns red after verification" do
      edit_gh { it["prs"]["1"]["checks"] = [{ "name" => "ci", "state" => "FAILURE", "bucket" => "fail" }] }

      expect(outcome.settle(checkout:, plan:, pull: pr, round:).kind).to eq(:rejected)
      expect(comments.first).to include("CI is red on PR #1 after verification.")
      expect(OpenLanes::Engine::Verification.latest(plan.feature.path).report.verdict).to eq(:rejected)
    end
  end
end
