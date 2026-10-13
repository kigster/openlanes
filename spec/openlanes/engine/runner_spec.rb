# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Runner, :tree do
  subject(:runner) { described_class.new(tree:, executor:, agents:, sleeper: ->(_) {}) }

  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agents) { OpenLanes::Agents::Registry.new }

  # The executor is the seam. Nothing in the suite invokes `claude`, so the
  # loop's logic is tested without a model, a network or a bill.
  let(:executor) { ->(agent, subject, **) { record(agent, subject) } }
  let(:calls) { [] }

  # By default an agent does nothing and signs nothing, so no ledger line
  # justifies a move, the tree cannot change, and the dispatcher must run out
  # of eligible agents rather than spinning to the ceiling.
  def record(agent, subject)
    calls << [agent.name, subject.feature.ordinal.to_s]
    OpenLanes::Execution::Executor::Result.new(ok: true, note: "noop", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
  end

  describe "#call" do
    context "with plans in several states" do
      let!(:built) do
        plans do |t|
          t.plan "000.00", :new, "needs-a-spec", files: { "spec.md" => spec_body }
          t.plan "000.01",
            :researched,
            "needs-a-writer",
            files: { "spec.md" => "#{spec_body}\n## Research\n\nWhat was found.\n" }
          t.plan "001.00", :planned, "needs-a-plan", files: { "spec.md" => spec_body, "plan.md" => "# P", "plan-frontend.md" => "## F1" }
          t.plan "002.00", :blocked, "needs-a-human", files: { "blocked.md" => "B1. Which?" }
          t.plan "003.00", :approved, "finished", prs: [t.merged(3, "done")]
        end
      end

      # 001.00 already has spec.md and plan.md when the round starts, so
      # ⭐️ Planned now goes straight to the pair that handles it — luke-backend
      # and rey-frontend — rather than to palpatine-planner first, now that
      # Building has split in two.
      it "offers each plan to the agent that handles its state" do
        runner.call

        expect(calls.uniq).to contain_exactly(["leah-researcher", "000.00"],
          ["yoda-writer", "000.01"],
          ["luke-backend", "001.00"],
          ["rey-frontend", "001.00"])
      end

      # The relay's whole point. Both used to declare `handles: [new]`, agents
      # are offered work in definition order and the runner takes the first,
      # so yoda-writer won on alphabetical order alone — and wrote goals and
      # conclusions over documents nobody had researched. They now hold
      # adjacent states rather than the same one.
      it "researches before it writes, rather than the two contending for ⚪️ New" do
        runner.call

        aggregate_failures do
          expect(calls).to include(["leah-researcher", "000.00"])
          expect(calls.filter_map { |name, ordinal| ordinal if name == "yoda-writer" }).to all(eq("000.01"))
        end
      end

      # `q` asks running agents to write out and stop; the loop's own half of
      # the bargain is to start nothing new afterwards.
      it "starts nothing once q has quit the run" do
        OpenLanes::Execution::Control.quit!
        attempts = runner.call

        expect(attempts).to be_empty
        expect(calls).to be_empty
      ensure
        OpenLanes::Execution::Control.reset!
      end

      it "never offers a blocked plan to anyone — that is what blocked means" do
        runner.call

        expect(calls.map(&:last)).not_to include("002.00")
      end

      it "leaves finished plans alone" do
        runner.call

        expect(calls.map(&:last)).not_to include("003.00")
      end

      it "reports blocked plans so a human can see what is waiting on them" do
        runner.call

        expect(runner.blocked.map { |s| s.feature.ordinal.to_s }).to eq(["002.00"])
      end
    end

    describe "#settled?" do
      it "is true when every plan is done or deliberately parked" do
        plans do |t|
          t.plan "000.00", :approved, "shipped", prs: [t.merged(1, "x")]
          t.plan "001.00", :blocked, "waiting", files: { "blocked.md" => "B1" }
        end

        expect(runner).to be_settled
      end

      it "is false while anything is still workable" do
        plans { |t| t.plan "000.00", :new, "todo", files: { "spec.md" => spec_body } }

        expect(runner).not_to be_settled
      end
    end

    # `--plan` is what makes a batch-create skill safe: it hands off exactly
    # the plans it just minted, not a whole-tree loop that a second and third
    # batch would each start again on top of.
    describe "--plan scoping" do
      subject(:runner) { described_class.new(tree:, executor:, agents:, plans: [ordinal("000.00")], sleeper: ->(_) {}) }

      let!(:built) do
        plans do |t|
          t.plan "000.00", :new, "in-scope", files: { "spec.md" => spec_body }
          t.plan "001.00", :new, "out-of-scope", files: { "spec.md" => spec_body }
        end
      end

      def ordinal(text) = OpenLanes::Plans::Ordinal.parse(text)

      it "only offers work to the plans named" do
        runner.call

        expect(calls.map(&:last).uniq).to eq(["000.00"])
      end

      it "leaves an out-of-scope plan's state exactly as it found it" do
        runner.call

        expect(tree.reload.find(ordinal("001.00")).status.key).to eq(:new)
      end

      describe "#in_scope?" do
        it "is true for a named plan" do
          expect(runner.in_scope?(tree.find(ordinal("000.00")))).to be(true)
        end

        it "is false for one left out" do
          expect(runner.in_scope?(tree.find(ordinal("001.00")))).to be(false)
        end
      end

      describe "#settled? and #blocked, scoped" do
        let!(:built) do
          plans do |t|
            t.plan "000.00", :approved, "in-scope", prs: [t.merged(1, "x")]
            t.plan "001.00", :new, "out-of-scope", files: { "spec.md" => spec_body }
          end
        end

        it "does not count an out-of-scope plan against #settled?" do
          expect(described_class.new(tree:, executor:, agents:, plans: [ordinal("000.00")], sleeper: ->(_) {})).to be_settled
        end

        it "does not report an out-of-scope block" do
          plans { |t| t.plan "002.00", :blocked, "out-of-scope-block", files: { "blocked.md" => "B1" } }

          expect(described_class.new(tree:, executor:, agents:, plans: [ordinal("000.00")], sleeper: ->(_) {}).blocked).to be_empty
        end
      end

      context "with no --plan given" do
        subject(:runner) { described_class.new(tree:, executor:, agents:, sleeper: ->(_) {}) }

        it "runs the whole tree, as before" do
          runner.call

          expect(calls.map(&:last).uniq).to contain_exactly("000.00", "001.00")
        end
      end
    end

    # An executor that raises, a crashed harness rather than an agent that
    # failed politely, must land as a failed attempt on the plan it was
    # running, not abort the loop or vanish. Every invocation runs on its own
    # thread, so this is the only path a raise can take.
    describe "an executor that raises mid-round, in parallel" do
      subject(:runner) do
        described_class.new(tree:,
          executor: explosive,
          agents:,
          isolation: :worktree,
          jobs: 2,
          worktree:,
          sleeper: ->(_) {})
      end

      let(:checkout) do
        instance_double(OpenLanes::Vcs::Worktree::Checkout,
          branch: "kig/000.00-x",
          path:   "/does-not-exist",
          dirty?: false)
      end
      let(:worktree) { instance_double(OpenLanes::Vcs::Worktree, checkout_for: checkout) }

      let(:explosive) do
        ->(agent, subject, **) {
          raise "the harness blew up" if subject.feature.ordinal.to_s == "000.00"

          record(agent, subject)
        }
      end

      let!(:built) do
        plans do |t|
          t.plan "000.00", :new, "explodes", files: { "spec.md" => spec_body }
          t.plan "001.00", :new, "survives", files: { "spec.md" => spec_body }
        end
      end

      it "records the crash as a failed attempt on its own plan and keeps going for the other" do
        runner.call

        attempts = runner.attempts
        crashed = attempts.find { |a| a.ordinal == "000.00" }
        aggregate_failures do
          expect(attempts.map(&:ordinal)).to contain_exactly("000.00", "001.00")
          expect(crashed).to have_attributes(ok: false, agent: "leah-researcher", note: "the harness blew up")
        end
      end
    end
  end
end
