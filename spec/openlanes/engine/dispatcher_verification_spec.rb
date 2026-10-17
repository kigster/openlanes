# frozen_string_literal: true

require "rbconfig"
require "socket"

# Plan 014 inside the loop: hansolo's approval hands the plan to 🧪, chewie
# runs with the app up around it, and its verdict goes to the verification
# outcome. The outcome itself (commit, comment, label) is its own spec's;
# here it is a double, and what is asserted is what the loop hands it.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:stamp) { "2026-10-16 09:00:00 AM PDT" }
  let(:calls) { [] }
  let(:files) { { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## How to test\n\n1. Run it.\n" } }
  let(:outcome) { instance_double(OpenLanes::Engine::Verification::Outcome, labels: %w[review-approved], mismatch: nil) }
  let(:checkout) { instance_double(OpenLanes::Vcs::Worktree::Checkout, branch: "kig/014.00-x", path: File.dirname(plans_root)) }
  let(:worktree) { instance_double(OpenLanes::Vcs::Worktree, checkout_for: checkout) }
  let(:registry) { OpenLanes::Apps::Ports.new(path: File.join(plans_root, "..", "ports.json")) }
  let(:factory) { ->(**options) { OpenLanes::Apps::Supervisor.new(**options, registry:, ready_timeout: 10, poll: 0.05) } }
  let(:app) { nil }
  let(:driver) { OpenLanes::Engine::Verification::Driver.new(outcome:, worktree:, app:, supervisor_factory: factory) }
  let!(:children_before) { OpenLanes::Execution::Child.live }

  def result = OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 1, down: 1, subagents: 0, delegated: 0, seconds: 1.0)

  # Signs as the real agents do, after `work` has written what it writes.
  def executor(note, &work)
    lambda { |agent, subject, round: 1, **|
      calls << [agent.name, subject.status.key]
      work&.call(subject)
      file = File.join(subject.feature.path, agent.ledger.first)
      OpenLanes::Plans::Ledger.append(file, "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} (#{note}) ]")
      result
    }
  end

  def run(executor, only)
    runner = OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents: OpenLanes::Agents::Registry.new.only(*only),
      isolation: :shared,
      verification: driver,
      sleeper: ->(_) {})
    dispatcher = described_class.new(runner:, sleeper: ->(_) {})
    attempts = dispatcher.run
    [attempts, dispatcher]
  end

  def plan = tree.reload.find(OpenLanes::Plans::Ordinal.parse("014.00"))

  def round_dir = File.join(plan.feature.path, "verification", "1")

  def report(verdict) = ->(_) { File.write(File.join(round_dir, "report.md"), "Verdict: #{verdict}\n") }

  def alive_children = (OpenLanes::Execution::Child.live - children_before).select(&:alive?)

  describe "hansolo's approval" do
    before { plans { |t| t.plan "014.00", :in_review, "chewie", files:, prs: [t.open(7, "Chewie")] } }

    it "moves the plan to 🧪 instead of finishing it" do
      attempts, dispatcher = run(executor("approved"), %w[hansolo-reviewer])

      aggregate_failures do
        expect(plan.status.key).to eq(:verifying)
        expect(attempts.last).to have_attributes(to: :verifying)
        expect(attempts.last.note).to include("approved, on to 🧪 verification")
        expect(dispatcher.instance_variable_get(:@finished_plans)).not_to include("014.00")
      end
    end

    it "leaves a verdict other than review-approved at 👀, finished, saying why" do
      allow(outcome).to receive(:labels).and_return(%w[review-ok-not-perfect])

      attempts, = run(executor("approved"), %w[hansolo-reviewer])

      aggregate_failures do
        expect(plan.status.key).to eq(:in_review)
        expect(attempts.last.note).to include("awaiting merge", "labelled review-ok-not-perfect", "only review-approved")
      end
    end

    it "hands the plan straight on to chewie in the same run" do
      allow(outcome).to receive(:pass).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :committed, note: "verified PR #7; waiting on CI"))

      run(executor("approved") { |s| report("verified").call(s) if s.status.key == :verifying }, %w[hansolo-reviewer chewie-verifier])

      expect(calls).to eq([["hansolo-reviewer", :in_review], ["chewie-verifier", :verifying]])
    end
  end

  describe "chewie's verdict" do
    before { plans { |t| t.plan "014.00", :verifying, "chewie", files:, prs: [t.open(7, "Chewie")] } }

    it "on verified, has the outcome push final.png, and leaves the plan at 🧪 waiting on CI" do
      allow(outcome).to receive(:pass).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :committed, note: "verified PR #7; waiting on CI"))

      attempts, = run(executor("verified", &report("verified")), %w[chewie-verifier])

      aggregate_failures do
        expect(outcome).to have_received(:pass).with(checkout: checkout, plan: anything, pull: anything, round: anything)
        expect(attempts.last).to have_attributes(ok: true, to: :verifying)
        expect(attempts.last.note).to include("waiting on CI")
        expect(driver.awaiting_ci?(plan)).to be(true)
        expect(calls.size).to eq(1)
      end
    end

    it "on rejected, has the outcome reject it, and reports where the folder went" do
      allow(outcome).to receive(:reject) do
        plan.machine.promote!(:rejected)
        OpenLanes::Engine::Verification::Outcome::Result.new(kind: :rejected, note: "verification rejected PR #7, rejected 1 of 2", to: :rejected)
      end

      attempts, = run(executor("rejected", &report("rejected")), %w[chewie-verifier])

      aggregate_failures do
        expect(outcome).to have_received(:reject).with(checkout:, plan: anything, pull: anything, round: anything, why: nil)
        expect(attempts.last).to have_attributes(to: :rejected)
        expect(attempts.last.note).to include("rejected 1 of 2")
      end
    end

    it "tells chewie it verifies through the shell when the project declares no app" do
      allow(outcome).to receive(:pass).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :committed, note: "x"))
      note = nil

      run(executor("verified") { |s| note = File.read(File.join(round_dir, "app.md")).tap { report("verified").call(s) } }, %w[chewie-verifier])

      expect(note).to include("through the shell (M11)")
    end

    context "with an app" do
      let(:server) { File.expand_path("../../fixtures/apps/servers/server.rb", __dir__) }
      let(:app) do
        OpenLanes::Apps::Definition.new(kind: "web",
          processes: [OpenLanes::Apps::ProcessSpec.new(name: "web", start: "#{RbConfig.ruby} #{server} --port-env PORT_WEB", preview: true)])
      end

      it "runs chewie with the app up, and stops it afterwards" do
        allow(outcome).to receive(:pass).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :committed, note: "x"))
        seen = nil

        run(executor("verified") { |s|
          port = File.read(File.join(round_dir, "app.md"))[/PORT_WEB=(\d+)/, 1].to_i
          seen = begin
            Socket.tcp("127.0.0.1", port, connect_timeout: 1).close
            true
          rescue SystemCallError
            false
          end
          report("verified").call(s)
        },
          %w[chewie-verifier])

        expect([seen, alive_children, registry.entries]).to eq([true, [], {}])
      end
    end

    context "with an app that never becomes ready" do
      let(:app) do
        OpenLanes::Apps::Definition.new(kind: "web",
          processes: [OpenLanes::Apps::ProcessSpec.new(name: "web", start: "for i in $(seq 1 25); do echo boot $i; done; exit 2")])
      end

      it "rejects without ever starting chewie, quoting the app's last 20 lines" do
        allow(outcome).to receive(:reject).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :rejected, note: "verification rejected PR #7", to: :rejected))

        attempts, = run(executor("verified"), %w[chewie-verifier])

        aggregate_failures do
          expect(calls).to be_empty
          expect(outcome).to have_received(:reject)
            .with(hash_including(why: a_string_including("the app does not start: web exited with status 2", "boot 6\n", "boot 25")))
          expect(attempts.last.note).to start_with("the app does not start; verification rejected PR #7")
          expect(alive_children).to be_empty
        end
      end
    end
  end

  describe "a verified plan waiting on CI" do
    before do
      plans { |t| t.plan "014.00", :verifying, "chewie", files:, prs: [t.open(7, "Chewie")] }
      FileUtils.mkdir_p(File.join(plan.feature.path, "verification", "1"))
      File.write(File.join(plan.feature.path, "verification", "1", "report.md"), "Verdict: verified\n")
    end

    it "is never handed to chewie again, and is settled by the engine instead" do
      allow(outcome).to receive(:settle).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :ready, note: "PR #7 ready-to-merge"))
      runner = OpenLanes::Engine::Runner.new(tree:,
        executor: executor("verified"),
        agents: OpenLanes::Agents::Registry.new.only("chewie-verifier"),
        isolation: :shared,
        verification: driver,
        sleeper: ->(_) {})
      dispatcher = described_class.new(runner:, sleeper: ->(_) {})

      dispatcher.tick
      driver.join
      dispatcher.tick

      aggregate_failures do
        expect(calls).to be_empty
        expect(outcome).to have_received(:settle).once.with(checkout:, plan: anything, pull: anything, round: anything)
      end
    end

    it "says on the idle line that it waits on CI" do
      allow(outcome).to receive(:settle).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :waiting, note: "🧪 waiting on CI for PR #7"))
      allow(OpenLanes::UI).to receive(:log)
      runner = OpenLanes::Engine::Runner.new(tree:,
        executor: executor("verified"),
        agents: OpenLanes::Agents::Registry.new.only("chewie-verifier"),
        isolation: :shared,
        verification: driver,
        sleeper: ->(_) {})
      dispatcher = described_class.new(runner:, sleeper: ->(_) {}, stay: true)

      dispatcher.tick
      driver.join
      dispatcher.tick

      expect(OpenLanes::UI).to have_received(:log).with("idle: 014.00 🧪 waiting on CI for PR #7")
    end
  end
end
