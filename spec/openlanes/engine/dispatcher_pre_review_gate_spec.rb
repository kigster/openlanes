# frozen_string_literal: true

# A builder that signs Completed on a red suite goes back to its builder,
# mailed the failure, with nothing published and no reviewer started.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  before do
    Dir.chdir(File.dirname(plans_root))
    # Memoised here, on the example's thread: the executor first reads them
    # on a job thread while `attempts` holds RSpec's memo lock, and deadlocks.
    [calls, stamp]
    allow(publisher).to receive(:publish).and_return(publication)
    allow(OpenLanes::Engine::PreReviewGate).to receive(:call).and_return(*verdicts)
    plans { |t| t.plan "001.00", :building, "tic-tac-toe", files: }
  end

  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agents) { OpenLanes::Agents::Registry.new }
  let(:state) { OpenLanes::Engine::StateFile.new(path: OpenLanes::Engine::StateFile.for(tree)) }
  let(:stamp) { "2026-09-04 11:29:20 AM PDT" }
  let(:calls) { [] }
  let(:checkout) do
    instance_double(OpenLanes::Vcs::Worktree::Checkout, branch: "kig/001.00-tic-tac-toe", path: plans_root, dirty?: true)
  end
  let(:worktree) { instance_double(OpenLanes::Vcs::Worktree, checkout_for: checkout, refresh: nil, root: File.dirname(plans_root)) }
  let(:publisher) { instance_double(OpenLanes::Vcs::Publisher) }
  let(:url) { "https://github.com/example/repo/pull/12" }
  let(:publication) do
    OpenLanes::Vcs::Publisher::Publication.new(ordinal: OpenLanes::Plans::Ordinal.parse("001.00"),
      branch: checkout.branch,
      title: "[001.00](A) Tic Tac Toe",
      url:,
      refusal: nil)
  end
  let(:red) { OpenLanes::Engine::PreReviewGate::Verdict.new(passed: false, reason: "`just check-all` exited 1", log_tail: "3 examples, 1 failure\n") }
  let(:green) { OpenLanes::Engine::PreReviewGate::Verdict.new(passed: true, reason: "`just check-all` passed", log_tail: "") }
  let(:plan) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")) }
  let(:files) do
    { "spec.md" => "---\nstarts: building\n---\n#{spec_body}", "plan.md" => "# Plan\n\n## U1\n", "pull-requests.md" => "# Pull Requests\n" }
  end

  let(:executor) do
    lambda { |agent, subject, round: 1, **|
      calls << agent.name
      file = File.join(subject.feature.path, agent.ledger.first)
      OpenLanes::Plans::Ledger.append(file, "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} ]")
      OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 10, down: 2, subagents: 0, delegated: 0, seconds: 1.0)
    }
  end
  let(:attempts) do
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents: agents.only("chores-coder"),
      isolation: :worktree,
      jobs: 1,
      worktree:,
      publisher:,
      state:,
      extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false),
      sleeper: ->(_) {}).call
  end
  let(:mail) { OpenLanes::Plans::Mailbox.new(dir: plan.feature.path).for("chores-coder") }

  context "when the suite is red, then green" do
    let(:verdicts) { [red, green] }

    it "bounces the first build to its builder with the log tail, and publishes the second" do
      attempts
      aggregate_failures do
        expect(calls).to eq(%w[chores-coder chores-coder])
        expect(attempts.first).to have_attributes(ok: false, status: "Interrupted")
        expect(attempts.first.note).to include("pre-review gate red: `just check-all` exited 1")
        expect([mail.first.from, mail.first.body]).to match(["openlanes", include("No reviewer was started", "3 examples, 1 failure")])
        expect(publisher).to have_received(:publish).once
        expect(plan.status.key).to eq(:ready_for_review)
      end
    end
  end

  context "when the suite stays red" do
    let(:verdicts) { [red] }

    it "never publishes and leaves the plan with its builder" do
      attempts
      aggregate_failures do
        expect(publisher).not_to have_received(:publish)
        expect(plan.status.key).to eq(:building)
        expect(attempts.map(&:ok).uniq).to eq([false])
        # The gate hands the round back GATE_BOUNCES times; every round after
        # that is "still red" and spends the runner's own retry budget, so
        # the run ends without a reviewer.
        expect(attempts.count { it.note.include?("back to chores-coder") }).to eq(described_class::Rename::GATE_BOUNCES)
        expect(attempts.size).to be > described_class::Rename::GATE_BOUNCES
        expect(attempts.last.note).to include("still red after")
      end
    end
  end

  context "when review.gate is false" do
    let(:verdicts) { [red] }

    before { File.write(File.join(File.dirname(plans_root), ".openlanes.yml"), "review:\n  gate: false\n") }

    it "runs no gate and goes on to review" do
      attempts
      aggregate_failures do
        expect(OpenLanes::Engine::PreReviewGate).not_to have_received(:call)
        expect(publisher).to have_received(:publish).once
        expect(plan.status.key).to eq(:ready_for_review)
      end
    end
  end
end
