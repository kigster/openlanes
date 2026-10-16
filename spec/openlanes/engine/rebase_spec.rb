# frozen_string_literal: true

# A real conflict in a real worktree, resolved by stand-in agents that do
# what the prompt asks: edit, `git add`, stop. The harness's own git steps
# run for real.
RSpec.describe OpenLanes::Engine::Rebase, :origin do
  subject(:rebases) { described_class.new(agents:, executor:) }

  let(:tmp) { Dir.mktmpdir("openlanes-rebase") }
  let(:main) { File.join(tmp, "project") }
  let(:upstream) { publish_with_origin(main, tmp) }
  let(:agents) { OpenLanes::Agents::Registry.new }
  let(:luke) { agents.find("luke-backend") }
  let(:worktrees) { OpenLanes::Vcs::Worktree.new(root: main, dir: File.join(tmp, "project.worktrees"), user: "tester", seeder: nil) }
  let(:feature) do
    OpenLanes::Plans::Feature.new(ordinal: OpenLanes::Plans::Ordinal.parse("008.01"),
      status: OpenLanes::Plans::STATUS_BY_KEY.fetch(:building),
      slug: "ewoki-linker",
      dirname: "008.01-🟡--ewoki-linker",
      path: File.join(main, OpenLanes::PLANS_DIR, "008.01-🟡--ewoki-linker"))
  end
  let(:plan) { Struct.new(:feature).new(feature) }
  let(:checkout) { worktrees.checkout_for(feature) }
  let(:calls) { [] }
  let(:resolve) { {} }
  let(:handle) { OpenLanes::Execution::Executor::Handle.new }

  # Records who was asked, as what, and for which files; resolves the files
  # when the agent's entry in +resolve+ says so. A resolution is checked
  # against the boundary exactly as the executor would check it.
  let(:executor) do
    lambda { |agent, _subject, root:, rebase:, **|
      calls << [agent.name, agent.model, agent.effort, rebase.files]
      before = OpenLanes::Execution::Boundary.snapshot(root)
      if (how = resolve[agent.name])
        File.write(File.join(root, "app.rb"), how)
        system("git", "-C", root, "add", "app.rb", out: File::NULL, err: File::NULL)
      end
      violation = before.violation(root)
      OpenLanes::Execution::Executor::Result.new(ok: violation.nil?,
        note: violation || "completed",
        up: 10,
        down: 2,
        subagents: 0,
        delegated: 0,
        seconds: 1.0)
    }
  end

  # The plan's own commit, before any rebase.
  let!(:own) do
    upstream
    commit_file(checkout.path, "app.rb", "one\nTWO from the plan\nthree\n")
  end

  after { FileUtils.rm_rf(tmp) }

  before { land(upstream, "app.rb", "one\ntwo from main\nthree\n") }

  def stopped = worktrees.refresh(checkout)
  def task(agent = luke) = OpenLanes::Engine::Runner::Task.new(agent:, subject: plan, root: checkout.path, checkout:, round: 1, refresh: stopped)
  def head = git!(checkout.path, "rev-parse", "HEAD")
  def origin_main = git!(main, "rev-parse", "refs/remotes/origin/main")

  context "when the plan's builder resolves the conflict" do
    before { resolve["luke-backend"] = "one\ntwo from main and the plan\nthree\n" }

    it "continues the rebase itself and reports success" do
      result = rebases.resolve(task, handle:)

      aggregate_failures do
        expect(result).to have_attributes(ok: true, up: 10, down: 2)
        expect(result.note).to include("rebased onto origin/main; luke-backend resolved 1 conflicted commit")
        expect(git!(checkout.path, "rev-parse", "HEAD~1")).to eq(origin_main)
        expect(File.read(File.join(checkout.path, "app.rb"))).to include("two from main and the plan")
        expect(calls.map(&:first)).to eq(["luke-backend"])
        expect(rebases.tally("008.01").failures).to eq(0)
      end
    end
  end

  context "when the builder leaves the conflict and bb8-resolver resolves it" do
    before { resolve["bb8-resolver"] = "one\ntwo, as bb8 resolved it\nthree\n" }

    it "hands the stopped rebase on, then continues it" do
      result = rebases.resolve(task, handle:)

      aggregate_failures do
        expect(calls.map(&:first)).to eq(%w[luke-backend bb8-resolver])
        expect(result.ok).to be(true)
        expect(result.note).to include("bb8-resolver resolved")
        expect(result.up).to eq(20)
      end
    end
  end

  context "when nobody resolves it" do
    it "aborts, restoring the branch exactly, and escalates bb8-resolver for the next run" do
      result = rebases.resolve(task, handle:)

      aggregate_failures do
        expect(result.ok).to be(false)
        expect(result.note).to include("aborted, branch restored",
          "bb8-resolver left app.rb unresolved",
          "retries on a later run as opus/high")
        expect(head).to eq(own)
        expect(rebases.resolvers(luke, "008.01").map { [it.name, it.model, it.effort] }).to eq([["bb8-resolver", "opus", "high"]])
      end
    end

    it "climbs the ladder, then waits for origin/main to move, then starts again" do
      described_class::LADDER.size.times { rebases.resolve(task, handle:) }

      aggregate_failures do
        expect(calls.map { it.first(3) }).to eq([["luke-backend", "opus", "high"], ["bb8-resolver", "sonnet", "high"],
                                                 ["bb8-resolver", "opus", "high"], ["bb8-resolver", "opus", "max"]])
        expect(rebases.hold("008.01")).to eq(origin_main)
        expect(worktrees.refresh(checkout, hold: rebases.hold("008.01")).kind).to eq(:pending)
        expect(head).to eq(own)
      end

      land(upstream, "lib/more.rb", "# more\n")
      calls.clear
      rebases.resolve(task, handle:)

      expect(calls.map(&:first)).to eq(%w[luke-backend bb8-resolver])
    end
  end

  context "when the assigned agent does not build" do
    let(:reviewer) { agents.find("hansolo-reviewer") }

    before { resolve["bb8-resolver"] = "resolved\n" }

    it "goes straight to bb8-resolver" do
      rebases.resolve(task(reviewer), handle:)

      expect(calls.map(&:first)).to eq(["bb8-resolver"])
    end
  end

  context "when two of the branch's commits conflict" do
    before do
      commit_file(checkout.path, "app.rb", "one\nTWO again\nthree\nfour\n")
      resolve["luke-backend"] = "one\ntwo from main\nthree\n"
    end

    it "invokes the resolver once per stop" do
      result = rebases.resolve(task, handle:)

      aggregate_failures do
        expect(calls.map(&:first)).to eq(%w[luke-backend luke-backend])
        expect(result.note).to include("resolved 2 conflicted commits")
      end
    end
  end

  context "when a resolver moves HEAD itself" do
    let(:executor) do
      lambda { |agent, _subject, root:, **|
        calls << agent.name
        system("git", "-C", root, "rebase", "--abort", out: File::NULL, err: File::NULL)
        OpenLanes::Execution::Executor::Result.new(ok: false,
          note: "agent committed (HEAD moved)",
          up: 0,
          down: 0,
          subagents: 0,
          delegated: 0,
          seconds: 0.0)
      }
    end

    it "fails the attempt with the boundary's reason and asks nobody else" do
      result = rebases.resolve(task, handle:)

      aggregate_failures do
        expect(calls).to eq(["luke-backend"])
        expect(result.note).to include("luke-backend: agent committed")
      end
    end
  end

  context "when a person stops the job" do
    let(:executor) do
      lambda { |agent, _subject, handle:, **|
        calls << agent.name
        handle.kill!(grace: 0)
        OpenLanes::Execution::Executor::Result.new(ok: false, note: "killed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
    end

    it "aborts at once" do
      result = rebases.resolve(task, handle:)

      aggregate_failures do
        expect(calls).to eq(["luke-backend"])
        expect(result.note).to include("stopped by request")
        expect(head).to eq(own)
      end
    end
  end

  context "when the executor raises" do
    let(:executor) { ->(*, **) { raise IOError, "pipe closed" } }

    it "aborts and reports the error" do
      result = rebases.resolve(task, handle:)

      aggregate_failures do
        expect(result.note).to include("IOError: pipe closed")
        expect(head).to eq(own)
      end
    end
  end

  context "when more commits conflict than one run allows" do
    before do
      stub_const("#{described_class}::STOPS", 1)
      commit_file(checkout.path, "app.rb", "one\nTWO again\nthree\nfour\n")
      resolve["luke-backend"] = "one\ntwo from main\nthree\n"
    end

    it "aborts rather than grinding on" do
      expect(rebases.resolve(task, handle:).note).to include("more than 1 commits conflicted")
    end
  end

  context "when continuing fails with nothing left to resolve" do
    let(:executor) do
      lambda { |_agent, _subject, root:, **|
        File.write(File.join(root, "app.rb"), "resolved\n")
        system("git", "-C", root, "add", "app.rb", out: File::NULL, err: File::NULL)
        lock = `git -C #{root} rev-parse --git-path index.lock`.strip
        File.write(File.expand_path(lock, root), "")
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
    end

    it "aborts with git's reason" do
      result = rebases.resolve(task, handle:)

      expect(result.note).to include("nothing unmerged")
    end
  end

  context "when bb8-resolver is not installed" do
    let(:agents) { OpenLanes::Agents::Registry.new.without("bb8-resolver") }

    it "lets the builder try, then aborts" do
      result = rebases.resolve(task, handle:)

      aggregate_failures do
        expect(calls.map(&:first)).to eq(["luke-backend"])
        expect(result.ok).to be(false)
      end
    end
  end
end
