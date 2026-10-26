# frozen_string_literal: true

# Plan 015 inside the loop: the real arbitrator step over a real `.plans`
# tree, its rulings applied by the real Effects against the fake `gh`. Only
# the agents are canned: the builders by a lambda that signs as they do, and
# the arbitrator by `ask`, which returns its ruling block as its final text.
RSpec.describe OpenLanes::Engine::Dispatcher, :fake_gh, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:calls) { [] }
  let(:asked) { [] }
  let(:thinking) { 0 }
  let(:answer) { "```ruling\nkind: cap\npr: 7\noutcome: no_go\nreason: F1 still corrupts the ledger.\n```\n" }
  let(:arbitration) do
    OpenLanes::Engine::Arbitration.new(tree_dir: plans_root,
      agents:       OpenLanes::Agents::Registry.new,
      github:       OpenLanes::Vcs::GitHub.new,
      max_rejections: -> { 2 },
      quality:      -> {},
      ask:          lambda { |agent, subject, _brief|
        sleep(thinking)
        asked << [agent.name, subject.status.key, calls.dup]
        answer
      })
  end

  def result = OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 1, down: 1, subagents: 0, delegated: 0, seconds: 1.0)

  def executor
    lambda { |agent, subject, round: 1, **|
      calls << [agent.name, subject.status.key]
      OpenLanes::Plans::PlanState.for(subject.feature.path).sign!(agent: agent.name, round:, status: "Completed", note: "fixed")
      result
    }
  end

  def run(dry_run: false, with: arbitration)
    runner = OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:      OpenLanes::Agents::Registry.new.only("backend-coder", "frontend-coder"),
      isolation:   :shared,
      dry_run:,
      arbitration: with,
      rounds:      1,
      sleeper:     ->(_) {})
    described_class.new(runner:, sleeper: ->(_) {}).run
  end

  def plan = tree.reload.find(OpenLanes::Plans::Ordinal.parse("015.00"))
  def state = OpenLanes::Plans::PlanState.for(plan.feature.path)
  def sign(agent, note) = state.sign!(agent:, round: 1, status: "Completed", note:)

  before do
    plans { |t| t.plan "015.00", :rejected, "arbiter", files: { "spec.md" => spec_body, "plan.md" => "## U1" }, prs: [t.open(7, "Arbiter")] }
    edit_gh do |gh|
      gh["labels"] = OpenLanes::Plans::ReviewLabel.known
      gh["prs"] = { "7" => gh_pr(title: "Arbiter", url: "https://github.com/example/repo/pull/7", labels: %w[review-rejected]) }
    end
  end

  describe "a plan at the cap" do
    before do
      sign("staff-reviewer", "rejected 1/2")
      sign("verifier", "rejected: CI is red")
    end

    it "is kept from its builders, ruled on, and a no_go blocks it" do
      run

      aggregate_failures do
        expect(calls).to eq([])
        expect(asked.map(&:first)).to eq(%w[arbitrator])
        expect(plan.status.key).to eq(:blocked)
        expect(state.rulings.map { it.values_at("kind", "outcome") }).to eq([%w[cap no_go]])
      end
    end

    context "with a go ruling" do
      let(:answer) { "```ruling\nkind: cap\npr: 7\noutcome: go\nreason: Only minor findings remain.\n```\n" }

      it "moves the plan on before any builder is assigned to it at 🔴" do
        run

        aggregate_failures do
          expect(plan.status.key).to eq(:ready_for_review)
          expect(gh.dig("prs", "7", "labels")).to include("ready-to-merge")
          expect(calls).not_to include(["backend-coder", :rejected], ["frontend-coder", :rejected])
        end
      end
    end

    it "runs no arbitrator on a dry run" do
      run(dry_run: true)
      expect([asked, state.rulings]).to eq([[], []])
    end
  end

  describe "an appeal on a plan below the cap" do
    let(:answer) { "```ruling\nkind: appeal\npr: 7\noutcome: upheld\nreason: F2 holds.\n```\n" }
    # Long enough for a builder the loop wrongly started to have been called.
    let(:thinking) { 0.3 }

    before { sign("backend-coder", "appeal: F2 because the spec rules that test out") }

    it "keeps the builders off the plan while the arbitrator is asked, then lets them on" do
      run

      aggregate_failures do
        expect(asked.map(&:last)).to eq([[]])
        expect(state.rulings.map { it.values_at("kind", "outcome") }).to eq([%w[appeal upheld]])
        expect(calls.map(&:first)).to include("backend-coder")
      end
    end
  end

  it "leaves a run without an arbitrator alone" do
    sign("staff-reviewer", "rejected 1/2")
    sign("verifier", "rejected: CI is red")
    run(with: nil)
    expect(calls.map(&:first)).to include("backend-coder")
  end

  describe OpenLanes::Engine::RunWorkflow do
    def workflow = described_class.new(tree:, isolation: "shared", dry_run: false, until_settled: true, web: false)

    it "builds no arbitrator for a run that publishes nothing" do
      worktree = instance_double(OpenLanes::Vcs::Worktree)
      expect([workflow.send(:arbitration_for, nil, worktree), workflow.send(:arbitration_for, Object.new, nil)]).to eq([nil, nil])
    end

    it "builds one for a run that publishes, under the run's own executor options" do
      built = workflow.send(:arbitration_for, Object.new, instance_double(OpenLanes::Vcs::Worktree))
      expect(built).to be_a(OpenLanes::Engine::Arbitration)
    end
  end
end
