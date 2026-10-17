# frozen_string_literal: true

require "rbconfig"
require "socket"

# Plan 014 end to end: hansolo approves, the folder goes 👀 → 🧪, the app
# runs while chewie verifies, and the engine commits, comments and labels.
# Real git with a bare origin and worktree isolation, the real `.plans`
# tree, the real publisher and GitHub seam answered by the fake `gh`, and
# 012's fixture server as the app. The one stand-in is for the agents: a
# lambda signs where `claude` would, writing what chewie-verifier.md asks
# chewie to write.
RSpec.describe "Verification, end to end", :fake_gh, :tree do
  let(:repo) { File.dirname(plans_root) }
  let(:origin) { Dir.mktmpdir("openlanes-origin") }
  let(:worktrees) { Dir.mktmpdir("openlanes-worktrees") }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:stamp) { "2026-10-16 09:00:00 AM PDT" }
  let(:png) { File.binread(File.expand_path("../fixtures/verification/step.png", __dir__)) }
  let(:server) { File.expand_path("../fixtures/apps/servers/server.rb", __dir__) }
  # Away from the floor the 012 specs reserve from, so a server of theirs
  # still shutting down never answers for this one.
  let(:registry) { OpenLanes::Apps::Ports.new(path: File.join(fake_gh_home, "ports.json"), floor: 11_900) }
  let(:factory) { ->(**options) { OpenLanes::Apps::Supervisor.new(**options, registry:, ready_timeout: 10, poll: 0.05) } }
  let(:gate_verdict) { OpenLanes::Engine::CoverageGate::Verdict.new(passed: true, reason: "coverage 97.00% meets the 95% minimum (simplecov: x)") }
  let(:gate) { instance_double(OpenLanes::Engine::CoverageGate, call: gate_verdict) }
  let(:worktree) { OpenLanes::Vcs::Worktree.new(root: repo, dir: worktrees, user: "tester", seeder: nil) }
  let(:publisher) { OpenLanes::Vcs::Publisher.new(root: repo, dry_run: false) }
  let(:app) { web_app("#{RbConfig.ruby} #{server} --name web --port-env PORT_WEB") }
  let(:driver) do
    agents = OpenLanes::Agents::Registry.new
    outcome = OpenLanes::Engine::Verification.outcome(root: repo,
      publisher:,
      github: OpenLanes::Vcs::GitHub.new,
      outcomes: OpenLanes::Engine::PrOutcomes.new(tree_dir: plans_root, agents:),
      agents:,
      coverage_gate: gate,
      max_rejections: 2)
    OpenLanes::Engine::Verification::Driver.new(outcome:, worktree:, app:, supervisor_factory: factory, interval: 0)
  end
  let(:app_seen) { [] }
  let!(:children_before) { OpenLanes::Execution::Child.live }

  def web_app(start) = OpenLanes::Apps::Definition.new(kind: "web", processes: [OpenLanes::Apps::ProcessSpec.new(name: "web", start:, preview: true)])

  def git(*args, dir: repo) = system("git", "-C", dir, *args, out: File::NULL, err: File::NULL) || raise("git #{args.join(" ")} failed")

  def plan = tree.reload.find(OpenLanes::Plans::Ordinal.parse("014.00"))

  def branch = worktree.branch_for(plan.feature)

  def on_origin = IO.popen(["git", "-C", origin, "ls-tree", "-r", "-z", "--name-only", branch], &:read).split("\0")

  def labels = gh.dig("prs", "1", "labels") & OpenLanes::Plans::ReviewLabel.names

  def comments = gh.dig("prs", "1", "comments").map { it["body"] }

  def mail_to = OpenLanes::Plans::Mailbox.new(dir: plan.feature.path).messages.map(&:to)

  def alive_children = (OpenLanes::Execution::Child.live - children_before).select(&:alive?)

  def checks(bucket) = edit_gh { it["prs"]["1"]["checks"] = [{ "name" => "ci", "state" => bucket.upcase, "bucket" => bucket }] }

  # What hansolo and chewie would leave, signed as each would sign it.
  def agent(verdict: "verified", failing: nil)
    lambda { |agent, subject, round: 1, **|
      note = agent.name == "hansolo-reviewer" ? "approved" : chewie(subject, verdict, failing)
      OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, agent.ledger.first),
        "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} (#{note}) ]")
      OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 1, down: 1, subagents: 0, delegated: 0, seconds: 1.0)
    }
  end

  def chewie(subject, verdict, failing)
    dir = OpenLanes::Engine::Verification.latest(subject.feature.path).dir
    port = File.read(File.join(dir, "app.md"))[/PORT_WEB=(\d+)/, 1].to_i
    app_seen << begin
      Socket.tcp("127.0.0.1", port, connect_timeout: 1).close
      true
    rescue SystemCallError
      false
    end
    %w[step-01.png step-02.png final.png].each { File.binwrite(File.join(dir, it), png) }
    failed = "\n## Failing step\n\n- Step: #{failing}\n- What: Press Go\n- Expected: the board\n- Seen: a blank page\n" if failing
    File.write(File.join(dir, "report.md"), "# Verification, round 1\n\nVerdict: #{verdict}\n#{failed}")
    verdict
  end

  def run(executor)
    runner = OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents: OpenLanes::Agents::Registry.new.only("hansolo-reviewer", "chewie-verifier"),
      isolation: :worktree,
      worktree:,
      publisher:,
      verification: driver,
      sleeper: ->(_) {})
    attempts = runner.call
    [runner, attempts]
  end

  # The CI look a staying run takes every 15 s, taken once by hand.
  def look(runner)
    dispatcher = OpenLanes::Engine::Dispatcher.new(runner:, sleeper: ->(_) {})
    dispatcher.tick
    driver.join
    dispatcher.tick
  end

  before do
    plans do |t|
      t.plan "014.00",
        :in_review,
        "go-button",
        files: { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## How to test\n\n1. Open the page.\n2. Press Go.\n" },
        prs:   [t.pr(1, "Go button", "Open 🟡").merge(url: "https://github.com/acme/widgets/pull/1")]
    end
    git("init", "-q", "--initial-branch=main")
    git("config", "user.email", "ada@example.com")
    git("config", "user.name", "Ada")
    git("config", "commit.gpgsign", "false")
    git("add", "-A")
    git("commit", "-qm", "initial")
    git("init", "-q", "--bare", dir: origin)
    git("remote", "add", "origin", origin)
    git("push", "-q", "origin", "main")
    edit_gh do |state|
      state["labels"] = OpenLanes::Plans::ReviewLabel.names
      state["prs"] = { "1" => gh_pr(title: "Go button",
        url: "https://github.com/acme/widgets/pull/1",
        branch: worktree.branch_for(plan.feature),
        labels: %w[review-approved]) }
    end
  end

  after { [origin, worktrees].each { FileUtils.rm_rf(it) } }

  it "takes a passing PR from approval to ready-to-merge once CI is green" do
    runner, attempts = run(agent)
    pushed = on_origin.grep(%r{/verification/1/}).map { File.basename(it) }
    checks("pending")
    look(runner)
    waiting = labels
    checks("pass")
    look(runner)

    aggregate_failures do
      expect(attempts.map { [it.agent, it.from, it.to] })
        .to eq([["hansolo-reviewer", :in_review, :verifying], ["chewie-verifier", :verifying, :verifying]])
      expect(app_seen).to eq([true])
      expect(pushed).to contain_exactly("final.png", "report.md")
      expect(waiting).to eq(%w[review-approved])
      expect(labels).to eq(%w[ready-to-merge])
      expect(plan.status.key).to eq(:verifying)
      expect(gh_calls.map { it.take(2) }).not_to include(%w[pr merge])
      expect(alive_children).to be_empty
    end
  end

  it "rejects a PR whose step fails, with the step's PNG linked by SHA, and sends it to the builders" do
    run(agent(verdict: "rejected", failing: 2))
    sha = IO.popen(["git", "-C", origin, "rev-parse", branch], &:read).strip
    pushed = on_origin.grep(%r{/verification/1/})

    aggregate_failures do
      expect(labels).to eq(%w[review-rejected])
      expect(comments.size).to eq(1)
      expect(comments.first).to include("**Step 2:** Press Go", "**Seen:** a blank page")
      expect(comments.first).to match(%r{\(https://github\.com/acme/widgets/blob/#{sha}/\.plans/[^)]+/verification/1/step-02\.png\?raw=true\)})
      expect(pushed.map { File.basename(it) }).to contain_exactly("step-02.png", "final.png", "report.md")
      expect(plan.status.key).to eq(:rejected)
      expect(mail_to).to include("luke-backend", "rey-frontend")
      expect(alive_children).to be_empty
    end
  end

  context "with an app whose process never becomes ready" do
    let(:app) { web_app("for i in $(seq 1 30); do echo booting $i; done; exit 5") }

    it "rejects without running chewie, quoting the last 20 lines of its output" do
      _, attempts = run(agent)

      aggregate_failures do
        expect(app_seen).to be_empty
        expect(attempts.last.note).to start_with("the app does not start")
        expect(labels).to eq(%w[review-rejected])
        expect(comments.first).to include("the app does not start: web exited with status 5", "booting 11\n", "booting 30\n")
        expect(comments.first).not_to include("booting 10\n")
        expect(plan.status.key).to eq(:rejected)
        expect(mail_to).to include("luke-backend", "rey-frontend")
      end
    end
  end
end
