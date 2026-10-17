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
      coverage_gate: gate,
      max_rejections: 2,
      arbitration:,
      screenshots: ->(dir) { OpenLanes::Engine::Verification::Screenshots.new(dir:, which: ->(_) { false }) })
  end

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

    it "rejects when CI turns red after verification" do
      edit_gh { it["prs"]["1"]["checks"] = [{ "name" => "ci", "state" => "FAILURE", "bucket" => "fail" }] }

      expect(outcome.settle(checkout:, plan:, pull: pr, round:).kind).to eq(:rejected)
      expect(comments.first).to include("CI is red on PR #1 after verification.")
      expect(OpenLanes::Engine::Verification.latest(plan.feature.path).report.verdict).to eq(:rejected)
    end
  end
end
