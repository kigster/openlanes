# frozen_string_literal: true

require "rbconfig"
require "socket"

# Plan 014 inside the loop: staff-reviewer's approval hands the plan to 🧪, verifier
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

  describe "staff-reviewer's approval" do
    before { plans { |t| t.plan "014.00", :in_review, "verifier", files:, prs: [t.open(7, "verifier")] } }

    it "moves the plan to 🧪 instead of finishing it" do
      attempts, dispatcher = run(executor("approved"), %w[staff-reviewer])

      aggregate_failures do
        expect(plan.status.key).to eq(:verifying)
        expect(attempts.last).to have_attributes(to: :verifying)
        expect(attempts.last.note).to include("approved, on to 🧪 verification")
        expect(dispatcher.instance_variable_get(:@finished_plans)).not_to include("014.00")
      end
    end

    it "leaves a verdict that goes nowhere at 👀, finished, saying why" do
      allow(outcome).to receive(:labels).and_return(%w[review-in-progress])

      attempts, = run(executor("approved"), %w[staff-reviewer])

      aggregate_failures do
        expect(plan.status.key).to eq(:in_review)
        expect(attempts.last.note).to include("awaiting merge", "labelled review-in-progress", "only review-approved")
      end
    end

    describe "a review-passed verdict (R4)" do
      let(:driver) { OpenLanes::Engine::Verification::Driver.new(outcome:, worktree:, app:, supervisor_factory: factory, quality:) }

      before { allow(outcome).to receive(:labels).and_return(%w[review-passed]) }

      context "with desired_codebase_quality unset" do
        let(:quality) { nil }

        it "stays 👀 and says the key is to be set" do
          attempts, = run(executor("approved"), %w[staff-reviewer])

          aggregate_failures do
            expect(plan.status.key).to eq(:in_review)
            expect(attempts.last.note).to include("labelled review-passed", "desired_codebase_quality is not set", "asked in the drawer")
            expect(OpenLanes::Plans::PlanState.for(plan.feature.path).quality_ask).to include("asked_at")
          end
        end
      end

      context "with the key answered mid-run" do
        let(:answers) { [nil, :mvp] }
        let(:quality) { -> { answers.first } }

        it "reads the quality afresh at every hand-off" do
          run(executor("approved"), %w[staff-reviewer])
          expect(plan.status.key).to eq(:in_review)

          answers.shift
          expect(driver.hand_off(plan)).to include("on to 🧪 verification")
          expect(plan.status.key).to eq(:verifying)
        end
      end

      context "with high" do
        let(:quality) { :high }

        before do
          allow(outcome).to receive(:send_back_for_quality) do |plan:, pull:, quality:|
            plan.machine.promote!(:rejected)
            OpenLanes::Engine::Verification::Outcome::Result.new(kind: :rejected,
              note: "verification rejected PR ##{pull.number}, rejected 1 of 2; desired_codebase_quality is #{quality}",
              to: :rejected)
          end
        end

        it "goes back to 🔴 for backend-coder and frontend-coder, counted as a rejection by the outcome" do
          attempts, dispatcher = run(executor("approved"), %w[staff-reviewer])

          aggregate_failures do
            expect(outcome).to have_received(:send_back_for_quality).once
            expect(plan.status.key).to eq(:rejected)
            expect(attempts.last).to have_attributes(to: :rejected)
            expect(attempts.last.note).to include("sent back", "back to 🔴", "rejected 1 of 2", "desired_codebase_quality is high")
            expect(attempts.last.note).not_to include("approved,")
            expect(dispatcher.instance_variable_get(:@finished_plans)).not_to include("014.00")
          end
        end
      end

      context "with standard" do
        let(:quality) { :standard }

        before do
          allow(outcome).to receive(:send_back_for_quality) do |plan:, pull:, quality:|
            plan.machine.promote!(:building)
            OpenLanes::Engine::Verification::Outcome::Result.new(kind: :rejected,
              note: "verification rejected PR ##{pull.number}, rejected 1 of 2; desired_codebase_quality is #{quality}",
              to: :building)
          end
        end

        it "goes back to 🟡 for backend-coder and frontend-coder, counted as a rejection by the outcome (plan 035)" do
          attempts, dispatcher = run(executor("approved"), %w[staff-reviewer])

          aggregate_failures do
            expect(outcome).to have_received(:send_back_for_quality).with(plan: anything, pull: anything, quality: :standard)
            expect(plan.status.key).to eq(:building)
            expect(attempts.last).to have_attributes(to: :building)
            expect(attempts.last.note).to include("sent back", "back to 🟡", "desired_codebase_quality is standard")
            expect(attempts.last.note).not_to include("approved,")
            expect(dispatcher.instance_variable_get(:@finished_plans)).not_to include("014.00")
          end
        end
      end

      # Dispatcher#approved takes a 🔴 after the hand-off as the hand-off's
      # own result. Only the high path above may land there.
      %i[mvp].push(nil).each do |level|
        context "with #{level.inspect}, the only other qualities" do
          let(:quality) { level }

          it "never sends the plan to 🔴" do
            attempts, = run(executor("approved"), %w[staff-reviewer])

            aggregate_failures do
              expect(plan.status.key).not_to eq(:rejected)
              expect(attempts.last.to).not_to eq(:rejected)
            end
          end
        end
      end

      context "with mvp" do
        let(:quality) { :mvp }

        it "goes on to 🧪 as an approval does" do
          attempts, = run(executor("approved"), %w[staff-reviewer])

          aggregate_failures do
            expect(plan.status.key).to eq(:verifying)
            expect(attempts.last.note).to include("on to 🧪 verification")
          end
        end
      end
    end

    it "hands the plan straight on to verifier in the same run" do
      allow(outcome).to receive(:pass).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :committed, note: "verified PR #7; waiting on CI"))

      run(executor("approved") { |s| report("verified").call(s) if s.status.key == :verifying }, %w[staff-reviewer verifier])

      expect(calls).to eq([["staff-reviewer", :in_review], ["verifier", :verifying]])
    end
  end

  describe "verifier's verdict" do
    before { plans { |t| t.plan "014.00", :verifying, "verifier", files:, prs: [t.open(7, "verifier")] } }

    it "on verified, has the outcome push final.png, and leaves the plan at 🧪 waiting on CI" do
      allow(outcome).to receive(:pass).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :committed, note: "verified PR #7; waiting on CI"))

      attempts, = run(executor("verified", &report("verified")), %w[verifier])

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

      attempts, = run(executor("rejected", &report("rejected")), %w[verifier])

      aggregate_failures do
        expect(outcome).to have_received(:reject).with(checkout:, plan: anything, pull: anything, round: anything, why: nil)
        expect(attempts.last).to have_attributes(to: :rejected)
        expect(attempts.last.note).to include("rejected 1 of 2")
      end
    end

    it "tells verifier it verifies through the shell when the project declares no app" do
      allow(outcome).to receive(:pass).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :committed, note: "x"))
      note = nil

      run(executor("verified") { |s| note = File.read(File.join(round_dir, "app.md")).tap { report("verified").call(s) } }, %w[verifier])

      expect(note).to include("through the shell (M11)")
    end

    context "with an app" do
      let(:server) { File.expand_path("../../fixtures/apps/servers/server.rb", __dir__) }
      let(:app) do
        OpenLanes::Apps::Definition.new(kind: "web",
          processes: [OpenLanes::Apps::ProcessSpec.new(name: "web", start: "#{RbConfig.ruby} #{server} --port-env PORT_WEB", preview: true)])
      end

      it "runs verifier with the app up, and stops it afterwards" do
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
          %w[verifier])

        expect([seen, alive_children, registry.entries]).to eq([true, [], {}])
      end
    end

    context "with an app that never becomes ready" do
      let(:app) do
        OpenLanes::Apps::Definition.new(kind: "web",
          processes: [OpenLanes::Apps::ProcessSpec.new(name: "web", start: "for i in $(seq 1 25); do echo boot $i; done; exit 2")])
      end

      it "rejects without ever starting verifier, quoting the app's last 20 lines" do
        allow(outcome).to receive(:reject).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :rejected, note: "verification rejected PR #7", to: :rejected))

        attempts, = run(executor("verified"), %w[verifier])

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
      plans { |t| t.plan "014.00", :verifying, "verifier", files:, prs: [t.open(7, "verifier")] }
      FileUtils.mkdir_p(File.join(plan.feature.path, "verification", "1"))
      File.write(File.join(plan.feature.path, "verification", "1", "report.md"), "Verdict: verified\n")
      File.write(File.join(plan.feature.path, "verification", "1", "published.txt"), "abc1234\n")
      allow(outcome).to receive(:look).and_return(look)
    end

    let(:look) { OpenLanes::Engine::Verification::Outcome::Look.new(ci: :pending) }

    def runner_for(driver)
      OpenLanes::Engine::Runner.new(tree:,
        executor: executor("verified"),
        agents: OpenLanes::Agents::Registry.new.only("verifier"),
        isolation: :shared,
        verification: driver,
        sleeper: ->(_) {})
    end

    it "does not end, and lets nothing touch the plan, while its look is under way" do
      gate = Queue.new
      allow(outcome).to receive(:look) { gate.pop and look }
      allow(outcome).to receive(:settle).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :waiting, note: "🧪 waiting on CI for PR #7"))
      dispatcher = described_class.new(runner: runner_for(driver), sleeper: ->(_) {})

      dispatcher.tick
      during = [dispatcher.done?, dispatcher.send(:untouchable).include?("014.00")]
      gate << true
      driver.join
      dispatcher.tick

      aggregate_failures do
        expect(during).to eq([false, true])
        expect(outcome).to have_received(:settle).once
        expect(dispatcher.send(:untouchable)).not_to include("014.00")
        expect(dispatcher.done?).to be(true)
      end
    end

    it "is never handed to verifier again, and is settled by the engine instead" do
      allow(outcome).to receive(:settle).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :ready, note: "PR #7 ready-to-merge"))
      runner = OpenLanes::Engine::Runner.new(tree:,
        executor: executor("verified"),
        agents: OpenLanes::Agents::Registry.new.only("verifier"),
        isolation: :shared,
        verification: driver,
        sleeper: ->(_) {})
      dispatcher = described_class.new(runner:, sleeper: ->(_) {})

      dispatcher.tick
      driver.join
      dispatcher.tick

      aggregate_failures do
        expect(calls).to be_empty
        expect(outcome).to have_received(:settle).once.with(checkout:, plan: anything, pull: anything, round: anything, seen: look)
      end
    end

    it "says on the idle line that it waits on CI" do
      allow(outcome).to receive(:settle).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :waiting, note: "🧪 waiting on CI for PR #7"))
      allow(OpenLanes::UI).to receive(:log)
      runner = OpenLanes::Engine::Runner.new(tree:,
        executor: executor("verified"),
        agents: OpenLanes::Agents::Registry.new.only("verifier"),
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
