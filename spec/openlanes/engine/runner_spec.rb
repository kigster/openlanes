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
          sleeper: ->(_) {},
          # One crash, not the crash and the round granted after it (E1).
          extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false))
      end

      let(:checkout) do
        instance_double(OpenLanes::Vcs::Worktree::Checkout,
          branch: "kig/000.00-x",
          path:   "/does-not-exist",
          dirty?: false)
      end
      let(:worktree) { instance_double(OpenLanes::Vcs::Worktree, checkout_for: checkout, refresh: nil) }

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

  describe "plan dependencies" do
    def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

    let(:ready) { { "plan.md" => "# P", "plan-frontend.md" => "## F1" } }

    context "when 050 depends on an open 034" do
      let!(:built) do
        plans do |t|
          t.plan "034.00", :planned, "parser", files: { "spec.md" => spec_body, **ready }
          t.plan "050.00", :planned, "printer", files: { "spec.md" => needs("034.00"), **ready }
        end
      end

      it "starts only 034 and says why 050 waits" do
        runner.call

        expect(calls.map(&:last).uniq).to eq(["034.00"])
        expect(runner.held).to eq("050.00" => "waiting on 034.00")
      end
    end

    context "when 034 is done" do
      let!(:built) do
        plans do |t|
          t.plan "034.00", :approved, "parser", prs: [t.merged(34, "Ship")]
          t.plan "050.00", :planned, "printer", files: { "spec.md" => needs("034.00"), **ready }
        end
      end

      it "starts 050" do
        runner.call

        expect(calls.map(&:last).uniq).to eq(["050.00"])
        expect(runner.held).to be_empty
      end
    end

    # The dry-run graph is built apart from Tree#dependencies, so it must
    # read archive/ too, or `run -n` holds 050 that a real run starts.
    context "when a dry run finds the prerequisite already archived" do
      subject(:runner) { described_class.new(tree:, executor:, agents:, dry_run: true, sleeper: ->(_) {}) }

      let!(:built) do
        plans do |t|
          t.plan "034.00",
            :approved,
            "parser",
            prs:         [t.merged(34, "Ship")],
            under:       "archive",
            archived_on: Date.new(2026, 10, 1)
          t.plan "050.00", :planned, "printer", files: { "spec.md" => needs("034.00"), **ready }
        end
      end

      it "starts 050 and holds nothing" do
        runner.call

        aggregate_failures do
          expect(calls.map(&:last).uniq).to eq(["050.00"])
          expect(runner.held).to be_empty
        end
      end
    end

    context "when 034 and 050 wait on each other" do
      let!(:built) do
        plans do |t|
          t.plan "034.00", :planned, "parser", files: { "spec.md" => needs("050.00"), **ready }
          t.plan "050.00", :planned, "printer", files: { "spec.md" => needs("034.00"), **ready }
        end
      end

      it "starts neither and reports the cycle for both" do
        runner.call

        expect(calls).to be_empty
        expect(runner.held).to eq("034.00" => "cycle: 034.00 → 050.00 → 034.00",
          "050.00" => "cycle: 050.00 → 034.00 → 050.00")
      end
    end

    # A dry run renames nothing, so 034's folder still says In Review. The
    # dispatcher judges it by the ✅ its merged pull request justifies, and
    # the report must agree rather than call 050 waiting.
    context "when a dry run would reconcile the prerequisite to done" do
      subject(:runner) { described_class.new(tree:, executor:, agents:, dry_run: true, sleeper: ->(_) {}) }

      let!(:built) do
        plans do |t|
          t.plan "034.00", :in_review, "parser", files: { "spec.md" => spec_body, **ready }, prs: [t.merged(34, "Ship")]
          t.plan "050.00", :planned, "printer", files: { "spec.md" => needs("034.00"), **ready }
        end
      end

      it "starts 050 and holds nothing, leaving 034's folder name alone" do
        runner.call

        aggregate_failures do
          expect(calls.map(&:last).uniq).to eq(["050.00"])
          expect(runner.held).to be_empty
          expect(tree.reload.find("034.00").status.key).to eq(:in_review)
        end
      end
    end
  end

  # Plan 009: the sweep runs before every assignment, and a 💣 stops new
  # work. Ages come from backdated `Blocked` signatures, never a stubbed clock.
  describe "aging and the halt" do
    def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

    def plan_path(ordinal) = tree.reload.find(ordinal).feature.path

    def blocked_since(days)
      OpenLanes::Plans::PlanState.for(plan_path("001.00"))
                                 .sign!(agent: "luke-backend", round: 1, status: "Blocked", at: Time.now - (days * 86_400))
    end

    let(:ready) { { "plan.md" => "# P\n\n## U1\n", "plan-frontend.md" => "## F1" } }

    before do
      plans do |t|
        t.plan "001.00", :blocked, "feed", files: { "spec.md" => spec_body, "plan.md" => "# P", "blocked.md" => "## B1 Which feed?\n" }
        t.plan "002.00", :planned, "consumer", files: { "spec.md" => needs("001.00"), **ready }
        t.plan "003.00", :planned, "unrelated", files: { "spec.md" => spec_body, **ready }
      end
    end

    context "when a plan others wait on has been blocked eight days" do
      before { blocked_since(8) }

      it "bombs it, starts nothing new, and names it" do
        runner.call

        aggregate_failures do
          expect(calls).to be_empty
          expect(tree.reload.find("001.00").status.key).to eq(:bomb)
          expect(runner.halted_by.map { it.feature.ordinal.to_s }).to eq(%w[001.00])
          expect(runner).to be_halted
        end
      end

      it "works on under --ignore-bombs, with the 💣 still standing" do
        runner = described_class.new(tree:, executor:, agents:, ignore_bombs: true, sleeper: ->(_) {})
        runner.call

        aggregate_failures do
          expect(calls.map(&:last).uniq).to eq(%w[003.00])
          expect(runner.bombs.map { it.feature.ordinal.to_s }).to eq(%w[001.00])
          expect(runner).not_to be_halted
        end
      end

      it "bombs nothing on a dry run, yet halts as the real run would" do
        runner = described_class.new(tree:, executor:, agents:, dry_run: true, sleeper: ->(_) {})
        runner.call

        aggregate_failures do
          expect(calls).to be_empty
          expect(tree.reload.find("001.00").status.key).to eq(:blocked)
          expect(runner.halted_by.map { it.feature.ordinal.to_s }).to eq(%w[001.00])
        end
      end

      it "ages nothing when aging_since is today" do
        runner = described_class.new(tree:, executor:, agents:, aging_since: Date.today, sleeper: ->(_) {})
        runner.call

        expect(calls.map(&:last).uniq).to eq(%w[003.00])
        expect(runner).not_to be_halted
      end
    end

    context "when the page said resume anyway" do
      before do
        blocked_since(8)
        tree.reload.find("001.00").machine.promote!(:bomb)
      end

      it "works on while the expiry is ahead" do
        OpenLanes::Plans::PlanState.for(plan_path("001.00")).resume_anyway!(till: Time.now + 3600)
        runner.call

        expect(calls.map(&:last).uniq).to eq(%w[003.00])
        expect(runner.bombs.size).to eq(1)
      end

      it "halts again once it has passed" do
        OpenLanes::Plans::PlanState.for(plan_path("001.00")).resume_anyway!(till: Time.now - 1)
        runner.call

        expect(calls).to be_empty
      end
    end
  end
end
