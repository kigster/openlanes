# frozen_string_literal: true

# The conflict sweep (U2 to U4) through the whole loop, over a real worktree
# with a real `origin`: a pull request waiting to merge that no longer merges
# clean becomes a bb8-resolver job in its plan's checkout, and the result is
# pushed and asked about again. GitHub and the push are doubles.
RSpec.describe OpenLanes::Engine::Dispatcher, :origin, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agents) { OpenLanes::Agents::Registry.new.only("r2d2-mechanic", "bb8-resolver") }
  let(:calls) { [] }
  let(:resolution) { nil }
  let(:tmp) { Dir.mktmpdir("openlanes-dispatch-sweep") }
  let(:worktree) do
    OpenLanes::Vcs::Worktree.new(root: repo_root, dir: File.join(tmp, "project.worktrees"), user: "tester", seeder: nil)
  end
  let(:url) { "https://github.com/example/repo/pull/1" }
  let!(:waiting) { plans { |t| t.plan "001.00", :completed, "tic-tac-toe", prs: [t.open(1, "Part 1")] } }
  let(:upstream) { publish_with_origin(repo_root, tmp) }
  let(:plan) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")) }
  let(:checkout) { worktree.checkout_for(plan.feature) }
  let(:github) { instance_double(OpenLanes::Vcs::GitHub) }
  let(:publisher) { instance_double(OpenLanes::Vcs::Publisher, pushed!: nil) }
  let(:upkeep) { OpenLanes::Engine::PullRequestUpkeep.new(github:) }

  let(:executor) do
    lambda { |agent, _subject, root:, rebase: nil, **|
      calls << [agent.name, rebase ? :rebase : :work]
      if rebase && resolution
        File.write(File.join(root, "app.rb"), resolution)
        system("git", "-C", root, "add", "app.rb", out: File::NULL, err: File::NULL)
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
      publisher:,
      upkeep:,
      sleeper: ->(_) {}).call
  end

  after { FileUtils.rm_rf(tmp) }

  before do
    [waiting, calls, resolution, upkeep]
    upstream
    allow(github).to receive_messages(open_pulls_labelled: {},
      branch_head: "main-1",
      swap_label: [],
      comment: nil,
      pull_request: { number: 1, open: true, labels: %w[ready-to-merge], merge_state: "DIRTY" })
    commit_file(checkout.path, "app.rb", "one\nTWO from the plan\nthree\n")
    land(upstream, "app.rb", "one\ntwo from main\nthree\n")
  end

  context "when bb8-resolver resolves the conflict" do
    let(:resolution) { "one\ntwo from main and the plan\nthree\n" }

    it "labels the pull request, resolves it in the plan's checkout, and pushes the rebased branch" do
      attempts

      aggregate_failures do
        expect(calls).to eq([["bb8-resolver", :rebase]])
        expect(github).to have_received(:swap_label)
          .with(number: 1, add: OpenLanes::Plans::ReviewLabel::CONFLICTS, remove: ["conflicts-resolved"])
        expect(publisher).to have_received(:pushed!).with(having_attributes(path: checkout.path), "HEAD")
        expect(attempts.map(&:note).join).to include("PR #1 pushed after its rebase onto main")
        expect(File.read(File.join(checkout.path, "app.rb"))).to eq("one\ntwo from main and the plan\nthree\n")
        expect(plan.status.key).to eq(:completed)
      end
    end
  end

  context "when nobody can resolve it" do
    it "aborts, pushes nothing, never blocks the plan, and asks again for the ladder's next step (D10)" do
      attempts
      upkeep.sweep(tree.reload.subjects)

      aggregate_failures do
        expect(calls).to eq([["bb8-resolver", :rebase]])
        expect(attempts.map(&:note).join).to include("conflicts on PR #1: rebase onto")
        expect(github).to have_received(:pull_request).twice
        expect(publisher).not_to have_received(:pushed!)
        expect(plan.status.key).to eq(:completed)
        expect(File).not_to exist(File.join(plan.feature.path, "blocked.md"))
      end
    end
  end
end
