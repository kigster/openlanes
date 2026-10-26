# frozen_string_literal: true

# The engine step over a real `.plans` tree and the real GitHub seam,
# answered by the fake `gh`. Only the agent's answer is canned: `ask` stands
# where the executor runs claude, and returns a ruling block as its final text.
RSpec.describe OpenLanes::Engine::Arbitration, :fake_gh, :tree do
  subject(:arbitration) do
    described_class.new(tree_dir: plans_root,
      agents:,
      github:,
      ask: ->(agent, _plan, brief) { asked << [agent.name, brief]; answer },
      max_rejections: -> { 2 },
      quality: -> { quality },
      effects: OpenLanes::Arbitration::Effects.new(tree_dir: plans_root, github:),
      clock: -> { now })
  end

  let(:github) { OpenLanes::Vcs::GitHub.new }
  let(:agents) { OpenLanes::Agents::Registry.new }
  let(:asked) { [] }
  let(:quality) { nil }
  let(:state_key) { :rejected }
  let(:labels_now) { %w[review-rejected] }
  let(:answer) { "Ruled.\n\n```ruling\nkind: cap\npr: 7\noutcome: no_go\nreason: F1 still corrupts the ledger.\n```\n" }

  before do
    plans { |t| t.plan "015.00", state_key, "arbiter", files: { "spec.md" => spec_body, "plan.md" => "## U1" }, prs: [t.open(7, "Arbiter")] }
    edit_gh do |gh|
      gh["labels"] = OpenLanes::Plans::ReviewLabel.known
      gh["prs"] = { "7" => gh_pr(title: "Arbiter", url: "https://github.com/example/repo/pull/7", labels: labels_now) }
    end
  end

  # The clock the back-off reads; an example moves it on by hand.
  attr_writer :now

  def now = @now ||= Time.utc(2026, 10, 23, 12)
  def plan = OpenLanes::Plans::Tree.new(dir: plans_root).find("015.00")
  def state = OpenLanes::Plans::PlanState.for(plan.feature.path)
  def sign(agent, note) = state.sign!(agent:, round: 1, status: "Completed", note:)
  def comments = gh_calls.select { it.first(2) == %w[pr comment] }

  # One full arbitration: the tick that starts the agent on its thread,
  # then, once it answered, the tick that applies the answer.
  def rule
    arbitration.tick([plan])
    arbitration.join
    arbitration.tick([plan])
  end

  describe "at the cap" do
    before do
      sign("staff-reviewer", "rejected 1/2")
      sign("verifier", "rejected: CI is red")
    end

    it "holds the plan from its builders" do
      expect(arbitration.holds?(plan)).to be(true)
    end

    it "runs the arbitrator, and a no_go blocks the plan with the ruling quoted in blocked.md" do
      outcomes = rule

      aggregate_failures do
        expect(outcomes.map(&:trigger)).to eq(%w[cap])
        expect(asked.map(&:first)).to eq(%w[arbitrator])
        expect(plan.status.key).to eq(:blocked)
        expect(plan.read("blocked.md")).to include("## B1", "> F1 still corrupts the ledger.")
        expect(state.rulings.map { it.values_at("kind", "outcome", "trigger") }).to eq([%w[cap no_go cap]])
        expect(comments.size).to eq(1)
        expect(state.stages.last.values_at("agent", "status")).to eq(%w[arbitrator Completed])
      end
    end

    it "leaves the count reset once the cap was ruled on" do
      rule
      expect([OpenLanes::Arbitration.counter(agents:).call(plan), arbitration.holds?(plan)]).to eq([0, false])
    end

    context "when the answer has no ruling block" do
      let(:answer) { "I would rule go." }

      it "records an Interrupted stage and rules nothing" do
        outcome = rule.first

        aggregate_failures do
          expect(outcome.error).to include("no ```ruling block")
          expect(state.rulings).to eq([])
          expect(state.stages.last.values_at("status", "note")).to eq(["Interrupted", "the answer has no ```ruling block (attempt 1 of 3)"])
          expect(plan.status.key).to eq(:rejected)
        end
      end

      it "asks once across many ticks while it backs off" do
        rule
        5.times { rule }
        expect(asked.size).to eq(1)
      end

      it "asks again once the back-off is over, and blocks the plan after the last attempt" do
        described_class::ATTEMPTS.times do
          rule
          self.now += 3600
        end
        3.times { rule }

        aggregate_failures do
          expect(asked.size).to eq(described_class::ATTEMPTS)
          expect(plan.status.key).to eq(:blocked)
          expect(plan.read("blocked.md")).to include("## B1 The arbitrator could not rule at the rejection cap")
          expect(state.stages.count { it["agent"] == "arbitrator" && it["status"] == "Interrupted" }).to eq(3)
        end
      end
    end

    it "does not wait for the agent: the tick returns while it runs, with the plan held as asking" do
      gate = Queue.new
      waiting = described_class.new(tree_dir: plans_root,
        agents:,
        github:,
        max_rejections: -> { 2 },
        ask: ->(*) { gate.pop })

      aggregate_failures do
        expect(waiting.tick([plan])).to eq([])
        expect([waiting.asking, waiting.busy?]).to eq([%w[015.00], true])
        expect(waiting.tick([plan])).to eq([])
        expect(state.stages.last.values_at("status", "finished_at")).to eq(["Started", nil])
      end
      gate << answer
      waiting.join
      expect(waiting.tick([plan]).map(&:trigger)).to eq(%w[cap])
      expect([waiting.asking, waiting.busy?, plan.status.key]).to eq([[], false, :blocked])
    end

    context "when an effect fails after the plan moved" do
      let(:github) do
        Class.new(SimpleDelegator) do
          def comment(**) = raise(OpenLanes::Error, "gh pr comment: HTTP 502")
        end.new(OpenLanes::Vcs::GitHub.new)
      end

      it "closes the stage where the folder is now, and raises nothing out of the tick" do
        outcome = nil
        expect { outcome = rule.first }.not_to raise_error

        aggregate_failures do
          expect(outcome.error).to eq("gh pr comment: HTTP 502")
          expect(plan.status.key).to eq(:blocked)
          expect(state.stages.last.values_at("status", "finished_at")).to match(["Interrupted", a_kind_of(String)])
        end
      end
    end

    it "rules nothing when the trigger went away while the agent ran" do
      arbitration.tick([plan])
      arbitration.join
      plan.machine.promote!(:building_ui)

      aggregate_failures do
        expect(arbitration.tick([plan]).first.error).to eq("the cap no longer stands")
        expect(state.rulings).to eq([])
      end
    end
  end

  it "does not hold a plan below the cap" do
    sign("staff-reviewer", "rejected 1/2")
    expect([arbitration.holds?(plan), arbitration.tick([plan])]).to eq([false, []])
  end

  describe "an appeal" do
    let(:answer) { "```ruling\nkind: appeal\npr: 7\noutcome: struck\nfindings:\n  struck: [F2]\nreason: Out of scope.\n```\n" }

    before { sign("backend-coder", "appeal: F2 because the spec rules that test out") }

    it "produces exactly one appeal ruling, however many ticks follow" do
      3.times { rule }

      aggregate_failures do
        expect(state.rulings.map { it.values_at("kind", "outcome") }).to eq([%w[appeal struck]])
        expect(asked.last.last).to include("Raised by: backend-coder", "appeal: F2")
        expect(state.messages.map { it["to"] }).to include("backend-coder", "staff-reviewer")
      end
    end

    it "lists F2 as struck in staff-reviewer's next prompt" do
      rule
      staff_reviewer = agents.find("staff-reviewer")
      prompt = OpenLanes::Execution::Prompt.new(agent: staff_reviewer,
        subject: plan,
        root: "/repo",
        profile: OpenLanes::Agents::Profile.resolve(staff_reviewer),
        max_rejections: -> { 2 }).to_s
      expect(prompt).to include("never to be raised again", "- F2 of the review struck at")
    end
  end

  describe "a dispute" do
    let(:state_key) { :building }
    let(:answer) { "```ruling\nkind: dispute\npr: 7\nwinner: frontend-coder\nreason: The code wins.\n```\n" }

    before { state.message!(from: "frontend-coder", to: "arbitrator", body: "dispute: contract.md GET /plans shape") }

    it "rules once, mails both builders and acks the dispute" do
      2.times { rule }

      aggregate_failures do
        expect(state.rulings.map { it.values_at("kind", "winner") }).to eq([%w[dispute frontend-coder]])
        expect(state.messages.first["read"]).to eq("yes")
        expect(state.messages.drop(1).map { it["to"] }).to eq(%w[backend-coder frontend-coder])
      end
    end
  end

  describe "a review-ok-not-perfect verdict" do
    let(:state_key) { :in_review }
    let(:labels_now) { %w[review-ok-not-perfect] }
    let(:answer) { "```ruling\nkind: passed_check\npr: 7\noutcome: too_lenient\nreason: F1 is critical.\n```\n" }

    before { sign("staff-reviewer", "ok, not perfect") }

    context "with mvp" do
      let(:quality) { :mvp }

      it "is checked once, and too_lenient sends it to 🔴 labelled review-rejected" do
        2.times { rule }

        aggregate_failures do
          expect(state.rulings.map { it.values_at("kind", "outcome") }).to eq([%w[passed_check too_lenient]])
          expect(plan.status.key).to eq(:rejected)
          expect(gh.dig("prs", "7", "labels")).to include("review-rejected")
          expect(OpenLanes::Arbitration.counter(agents:).call(plan)).to eq(1)
        end
      end

      it "asks GitHub for the labels once per review, not once per tick" do
        quiet = described_class.new(tree_dir: plans_root,
          agents:,
          github:,
          quality: -> { :mvp },
          ask: ->(*) { "no block" },
          clock: -> { now })
        edit_gh { it["prs"]["7"]["labels"] = %w[review-in-progress] }
        4.times { quiet.tick([plan]) }
        expect(gh_calls.count { it.first(2) == %w[pr view] }).to eq(1)
      end

      context "when the plan is at 🟡" do
        let(:state_key) { :ready_for_review }

        it "runs no passed_check: 🔴 is reachable from 👀 only" do
          3.times { rule }
          expect([state.rulings, asked, gh.dig("prs", "7", "labels")]).to eq([[], [], %w[review-ok-not-perfect]])
        end
      end
    end

    [:high, nil].each do |level|
      context "with #{level.inspect}" do
        let(:quality) { level }

        it "runs no passed_check" do
          3.times { rule }
          expect([state.rulings, asked]).to eq([[], []])
        end
      end
    end
  end

  it "only logs when Outcome reports the cap" do
    expect { arbitration.call(plan:, count: 2, max: 2) }.not_to change(state, :rulings)
  end

  describe OpenLanes::Engine::Arbitration::Asker do
    let(:traces) { Dir.mktmpdir("openlanes-traces") }
    let(:ok) { OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 1, down: 1, subagents: 0, delegated: 0, seconds: 1.0) }
    let(:briefs) { [] }

    # Writes its trace where the real executor does, and names it on the
    # handle; a second trace for the same plan and agent is a decoy.
    def executor(result: ok, write: true)
      dir = traces
      lambda do |brief|
        briefs << brief
        lambda do |agent, subject, handle:|
          trace = File.join(dir, "20261021-000000-#{subject.feature.ordinal}-#{agent.name}-1-0001.ndjson")
          File.write(File.join(dir, "20261021-000001-#{subject.feature.ordinal}-#{agent.name}-1-0002.ndjson"),
            "#{JSON.generate(type: "result", result: "decoy")}\n")
          if write
            File.write(trace, "#{JSON.generate(type: "assistant")}\n#{JSON.generate(type: "result", result: "```ruling\nkind: cap\n```")}\n")
            handle.trace = trace
          end
          result
        end
      end
    end

    after { FileUtils.rm_rf(traces) }

    it "returns the final answer from the trace its own run wrote, given the brief" do
      asker = described_class.new(executor: executor)
      aggregate_failures do
        expect(asker.call(agents.find("arbitrator"), plan, "Trigger: cap")).to eq("```ruling\nkind: cap\n```")
        expect(briefs).to eq(["Trigger: cap"])
      end
    end

    it "returns nothing when no trace was written" do
      asker = described_class.new(executor: executor(write: false))
      expect(asker.call(agents.find("arbitrator"), plan, "Trigger: cap")).to eq("")
    end

    it "says the run failed rather than that the answer had no ruling" do
      asker = described_class.new(executor: executor(result: ok.with(ok: false, note: "claude exited 1: overloaded")))
      expect { asker.call(agents.find("arbitrator"), plan, "Trigger: cap") }
        .to raise_error(OpenLanes::Error, "the arbitrator's run failed: claude exited 1: overloaded")
    end
  end
end
