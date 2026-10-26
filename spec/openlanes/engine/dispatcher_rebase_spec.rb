# frozen_string_literal: true

# The whole loop over a real worktree with a real `origin`: the harness
# refreshes the plan's checkout before each agent, a stopped rebase becomes a
# job of its own, and plan work follows on the next tick.
RSpec.describe OpenLanes::Engine::Dispatcher, :origin, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agents) { OpenLanes::Agents::Registry.new.only("chores-coder", "rebaser") }
  let(:stamp) { "2026-10-16 09:00:00 AM PDT" }
  let(:calls) { [] }
  let(:resolution) { nil }
  let(:tmp) { Dir.mktmpdir("openlanes-dispatch-rebase") }
  let(:worktree) do
    OpenLanes::Vcs::Worktree.new(root: repo_root, dir: File.join(tmp, "project.worktrees"), user: "tester", seeder: nil)
  end
  let(:files) { { "spec.md" => "---\nstarts: building\n---\n#{spec_body}", "plan.md" => "# Plan\n\n## U1\n" } }
  let!(:built) { plans { |t| t.plan "001.00", :building, "tic-tac-toe", files: } }
  let(:upstream) { publish_with_origin(repo_root, tmp) }
  let(:plan) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")) }
  let(:checkout) { worktree.checkout_for(plan.feature) }

  # Rebase invocations stage +resolution+ when there is one; plan work signs
  # Completed. Each call records whether what landed upstream was there.
  let(:executor) do
    lambda { |agent, subject, root:, round: 1, rebase: nil, **|
      calls << [agent.name, rebase ? :rebase : :work, File.exist?(File.join(root, "lib/landed.rb"))]
      if rebase
        if resolution
          File.write(File.join(root, "app.rb"), resolution)
          system("git", "-C", root, "add", "app.rb", out: File::NULL, err: File::NULL)
        end
      else
        ledger = File.join(subject.feature.path, agent.ledger.first)
        OpenLanes::Plans::Ledger.append(ledger, "> [#{stamp}] [ agent: #{agent.name}   status: Started, round #{round} ]")
        OpenLanes::Plans::Ledger.append(ledger, "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} ]")
      end
      OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 1, down: 1, subagents: 0, delegated: 0, seconds: 0.1)
    }
  end
  let(:attempts) do
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :worktree,
      jobs: 1,
      worktree:,
      sleeper: ->(_) {}).call
  end

  after { FileUtils.rm_rf(tmp) }

  # Memoized before the run: the executor reads them from the agents'
  # threads, and RSpec's `let` lock is held by the thread running `attempts`.
  before do
    [built, stamp, calls, resolution]
    upstream
  end

  # Plan 008.01's case: nothing of its own, far behind.
  context "when the plan's branch has no commits of its own and is behind" do
    before do
      checkout
      3.times { land(upstream, "lib/landed#{"_#{it}" unless it == 2}.rb", "# landed\n") }
    end

    it "fast-forwards it before the agent runs, and no agent resolves anything" do
      attempts

      expect(calls).to eq([["chores-coder", :work, true]])
    end
  end

  context "when the plan's own commit conflicts with what landed" do
    before do
      commit_file(checkout.path, "app.rb", "one\nTWO from the plan\nthree\n")
      land(upstream, "app.rb", "one\ntwo from main\nthree\n")
      land(upstream, "lib/landed.rb", "# landed\n")
    end

    context "when the builder resolves it" do
      let(:resolution) { "one\ntwo from main and the plan\nthree\n" }

      it "spends one job on the rebase, then the plan's work on the rebased branch" do
        aggregate_failures do
          expect(attempts.first.note).to include("rebased onto origin/main; chores-coder resolved")
          expect(calls.map { it.first(2) }).to eq([["chores-coder", :rebase], ["chores-coder", :work]])
          expect(calls.last.last).to be(true)
          expect(git!(checkout.path, "log", "-1", "--format=%s")).to eq("edit app.rb")
        end
      end
    end

    context "when nobody can resolve it" do
      it "climbs rebaser's ladder, then lets the plan work on its old base, never blocking it" do
        attempts

        aggregate_failures do
          expect(calls.map { it.first(2) }).to eq([["chores-coder", :rebase], ["rebaser", :rebase],
                                                   ["rebaser", :rebase], ["rebaser", :rebase], ["chores-coder", :work]])
          expect(calls.last.last).to be(false)
          expect(attempts.map(&:note).join).to include("REBASE PENDING")
          expect(plan.status.key).to eq(:building)
          expect(File).not_to exist(File.join(plan.feature.path, "blocked.md"))
        end
      end
    end
  end
end
