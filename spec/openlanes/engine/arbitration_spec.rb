# frozen_string_literal: true

# The engine step over a real `.plans` tree and the real GitHub seam,
# answered by the fake `gh`. Only the agent's answer is canned: `ask` stands
# where the executor runs claude, and returns a ruling block as its final text.
RSpec.describe OpenLanes::Engine::Arbitration, :fake_gh, :tree do
  subject(:arbitration) do
    described_class.new(tree_dir: plans_root,
      agents:,
      github: OpenLanes::Vcs::GitHub.new,
      ask: ->(agent, _plan, brief) { asked << [agent.name, brief]; answer },
      max_rejections: -> { 2 },
      quality: -> { quality })
  end

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

  def plan = OpenLanes::Plans::Tree.new(dir: plans_root).find("015.00")
  def state = OpenLanes::Plans::PlanState.for(plan.feature.path)
  def sign(agent, note) = state.sign!(agent:, round: 1, status: "Completed", note:)
  def comments = gh_calls.select { it.first(2) == %w[pr comment] }

  describe "at the cap" do
    before do
      sign("hansolo-reviewer", "rejected 1/2")
      sign("chewie-verifier", "rejected: CI is red")
    end

    it "holds the plan from its builders" do
      expect(arbitration.holds?(plan)).to be(true)
    end

    it "runs the arbitrator, and a no_go blocks the plan with the ruling quoted in blocked.md" do
      outcomes = arbitration.tick([plan])

      aggregate_failures do
        expect(outcomes.map(&:trigger)).to eq(%w[cap])
        expect(asked.map(&:first)).to eq(%w[obi-wan-kenobi-arbitrator])
        expect(plan.status.key).to eq(:blocked)
        expect(plan.read("blocked.md")).to include("## B1", "> F1 still corrupts the ledger.")
        expect(state.rulings.map { it.values_at("kind", "outcome", "trigger") }).to eq([%w[cap no_go cap]])
        expect(comments.size).to eq(1)
        expect(state.stages.last.values_at("agent", "status")).to eq(%w[obi-wan-kenobi-arbitrator Completed])
      end
    end

    it "leaves the count reset once the cap was ruled on" do
      arbitration.tick([plan])
      expect([OpenLanes::Arbitration.counter(agents:).call(plan), arbitration.holds?(plan)]).to eq([0, false])
    end

    context "when the answer has no ruling block" do
      let(:answer) { "I would rule go." }

      it "records an Interrupted stage and rules nothing" do
        outcome = arbitration.tick([plan]).first

        aggregate_failures do
          expect(outcome.error).to include("no ```ruling block")
          expect(state.rulings).to eq([])
          expect(state.stages.last["status"]).to eq("Interrupted")
          expect(plan.status.key).to eq(:rejected)
        end
      end
    end
  end

  it "does not hold a plan below the cap" do
    sign("hansolo-reviewer", "rejected 1/2")
    expect([arbitration.holds?(plan), arbitration.tick([plan])]).to eq([false, []])
  end

  describe "an appeal" do
    let(:answer) { "```ruling\nkind: appeal\npr: 7\noutcome: struck\nfindings:\n  struck: [F2]\nreason: Out of scope.\n```\n" }

    before { sign("luke-backend", "appeal: F2 because the spec rules that test out") }

    it "produces exactly one appeal ruling, however many ticks follow" do
      3.times { arbitration.tick([plan]) }

      aggregate_failures do
        expect(state.rulings.map { it.values_at("kind", "outcome") }).to eq([%w[appeal struck]])
        expect(asked.last.last).to include("Raised by: luke-backend", "appeal: F2")
        expect(state.messages.map { it["to"] }).to include("luke-backend", "hansolo-reviewer")
      end
    end

    it "lists F2 as struck in hansolo's next prompt" do
      arbitration.tick([plan])
      hansolo = agents.find("hansolo-reviewer")
      prompt = OpenLanes::Execution::Prompt.new(agent: hansolo,
        subject: plan,
        root: "/repo",
        profile: OpenLanes::Agents::Profile.resolve(hansolo),
        max_rejections: -> { 2 }).to_s
      expect(prompt).to include("Struck by the arbitrator, never to be raised again: F2.")
    end
  end

  describe "a dispute" do
    let(:state_key) { :building }
    let(:answer) { "```ruling\nkind: dispute\npr: 7\nwinner: rey-frontend\nreason: The code wins.\n```\n" }

    before { state.message!(from: "rey-frontend", to: "obi-wan-kenobi-arbitrator", body: "dispute: contract.md GET /plans shape") }

    it "rules once, mails both builders and acks the dispute" do
      2.times { arbitration.tick([plan]) }

      aggregate_failures do
        expect(state.rulings.map { it.values_at("kind", "winner") }).to eq([%w[dispute rey-frontend]])
        expect(state.messages.first["read"]).to eq("yes")
        expect(state.messages.drop(1).map { it["to"] }).to eq(%w[luke-backend rey-frontend])
      end
    end
  end

  describe "a review-ok-not-perfect verdict" do
    let(:state_key) { :in_review }
    let(:labels_now) { %w[review-ok-not-perfect] }
    let(:answer) { "```ruling\nkind: passed_check\npr: 7\noutcome: too_lenient\nreason: F1 is critical.\n```\n" }

    before { sign("hansolo-reviewer", "ok, not perfect") }

    context "with mvp" do
      let(:quality) { :mvp }

      it "is checked once, and too_lenient sends it to 🔴 labelled review-rejected" do
        2.times { arbitration.tick([plan]) }

        aggregate_failures do
          expect(state.rulings.map { it.values_at("kind", "outcome") }).to eq([%w[passed_check too_lenient]])
          expect(plan.status.key).to eq(:rejected)
          expect(gh.dig("prs", "7", "labels")).to include("review-rejected")
          expect(OpenLanes::Arbitration.counter(agents:).call(plan)).to eq(1)
        end
      end
    end

    [:high, nil].each do |level|
      context "with #{level.inspect}" do
        let(:quality) { level }

        it "runs no passed_check" do
          3.times { arbitration.tick([plan]) }
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
    let(:fake) do
      Class.new do
        def initialize(dir) = @dir = dir

        def call(agent, subject)
          File.write(File.join(@dir, "20261021-000000-#{subject.feature.ordinal}-#{agent.name}-1-0001.ndjson"),
            "#{JSON.generate(type: "assistant")}\n#{JSON.generate(type: "result", result: "```ruling\nkind: cap\n```")}\n")
        end
      end
    end

    after { FileUtils.rm_rf(traces) }

    it "returns the final answer from the trace the executor wrote" do
      asker = described_class.new(root: "/repo", executor: ->(**) { fake.new(traces) }, trace_dir: traces)
      expect(asker.call(agents.find("obi-wan-kenobi-arbitrator"), plan, "Trigger: cap")).to eq("```ruling\nkind: cap\n```")
    end

    it "returns nothing when no trace was written" do
      asker = described_class.new(root: "/repo", executor: ->(**) { ->(_agent, _subject) {} }, trace_dir: traces)
      expect(asker.call(agents.find("obi-wan-kenobi-arbitrator"), plan, "Trigger: cap")).to eq("")
    end
  end
end
