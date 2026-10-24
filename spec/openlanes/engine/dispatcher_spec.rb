# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agents) { OpenLanes::Agents::Registry.new }
  let(:state) { OpenLanes::Engine::StateFile.new(path: OpenLanes::Engine::StateFile.for(tree)) }
  let(:calls) { [] }
  let(:stamp) { "2026-09-04 11:29:20 AM PDT" }
  # These examples are about the limits an agent is given; the round a run
  # grants on its own when nobody answers (E1) has its own spec.
  let(:limits) { OpenLanes::Engine::Extensions.new(stay: false, auto: false) }

  # An executor that behaves like a real agent: signs Started, does its
  # work, signs its outcome. Each fake is keyed by agent name.
  def executor_with(&behaviour)
    lambda { |agent, subject, round: 1, **|
      calls << [agent.name, subject.feature.ordinal.to_s, round]
      file = File.join(subject.feature.path, agent.ledger.first)
      OpenLanes::Plans::Ledger.append(file, "> [#{stamp}] [ agent: #{agent.name}   status: Started, round #{round} ]")
      outcome = behaviour.call(agent, subject, round)
      OpenLanes::Plans::Ledger.append(file, "> [#{stamp}] [ agent: #{agent.name}   status: #{outcome}, round #{round} ]") if outcome
      OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 10, down: 2, subagents: 0, delegated: 0, seconds: 1.0)
    }
  end

  # What ewoki-linker's one Edit does: answer `depends_on:` in spec.md.
  # 🔗 refuses to move on until it is answered.
  def link(subject)
    file = File.join(subject.feature.path, "spec.md")
    text = File.read(file)
    File.write(file, text.start_with?("---\n") ? text.sub("---\n", "---\ndepends_on: [none]\n") : "---\ndepends_on: [none]\n---\n#{text}")
  end

  def runner_with(executor, **)
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :shared,
      jobs: 2,
      state:,
      sleeper: ->(_) {},
      extensions: limits,
**)
  end

  def path_of(ordinal) = tree.reload.find(OpenLanes::Plans::Ordinal.parse(ordinal)).feature.path

  # What has been signed for a plan, in state.json: [status, round, note].
  def signed(ordinal) = OpenLanes::Plans::PlanState.for(path_of(ordinal)).signatures.map { it.values_at("status", "round", "note") }

  # The minesweeper trial: two jobs, and each agent's file written well
  # before it signed. The next tick read the half-finished folder as the next
  # state and started that state's agent beside the one still writing, the
  # first then held the folder for its "partner", and the whole chain ran
  # inside ⚪ New.
  describe "an agent whose work shows before it signs" do
    let!(:built) { plans { |t| t.plan "030.00", :new, "minesweeper", files: { "spec.md" => spec_body } } }
    let(:live) { Hash.new(0) }
    let(:overlaps) { [] }
    let(:seen) { [] }
    let(:plan) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("030.00")) }

    let!(:attempts) do
      [stamp, live, overlaps, seen]
      runner = OpenLanes::Engine::Runner.new(tree:,
        executor:  slow_executor,
        agents:    agents.only("leah-researcher", "yoda-writer"),
        isolation: :shared,
        jobs:      2,
        state:,
        sleeper:   ->(_) { sleep(0.02) })
      allow(runner).to receive(:jobs).and_return(2)
      runner.call
    end

    def slow_executor
      guard = Mutex.new
      lambda { |agent, subject, round: 1, **|
        ordinal = subject.feature.ordinal.to_s
        guard.synchronize do
          overlaps << [agent.name, live[ordinal]] if live[ordinal].positive?
          live[ordinal] += 1
          seen << [agent.name, subject.status.key]
        end
        write_work(agent, subject.feature.path)
        sleep(0.3) # several ticks pass with the work on disk and no signature
        OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, agent.ledger.first),
          "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} ]")
        guard.synchronize { live[ordinal] -= 1 }
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
    end

    def write_work(agent, dir)
      case agent.name
      when "leah-researcher" then File.write(File.join(dir, "spec.md"), "#{spec_body}\n## Research\n\nFound.\n")
      when "yoda-writer" then File.write(File.join(dir, "plan.md"), "")
      end
    end

    it "starts nobody else on the plan until the agent in it has finished" do
      expect(overlaps).to be_empty
    end

    it "moves the folder at each Completed, so each agent starts from the state it handles" do
      aggregate_failures do
        expect(seen).to eq([["leah-researcher", :new], ["yoda-writer", :researched]])
        expect(attempts.map { [it.agent, it.from, it.to] })
          .to eq([["leah-researcher", :new, :researched], ["yoda-writer", :researched, :ready_for_linking]])
        expect(plan.status.key).to eq(:ready_for_linking)
      end
    end

    it "records every stage as finished, in state.json and in the engine's state file alike" do
      stages = OpenLanes::Plans::PlanState.for(plan.feature.path).stages
      aggregate_failures do
        expect(stages.map { [it["agent"], it["status"], it["from"], it["to"]] })
          .to eq([%w[leah-researcher Completed new researched], %w[yoda-writer Completed researched ready_for_linking]])
        expect(state.stages("030.00").map { it["status"] }.uniq).to eq(["Completed"])
      end
    end
  end

  # The trial's own shape: worktree isolation in a real repository, two
  # jobs, agents writing into the plan folder in the main tree, as the prompt
  # tells them to. Whether `.plans` is committed or not, each plan's agents
  # run one at a time and every Completed moves the folder.
  describe "worktree isolation in a real repository" do
    let(:repo) { File.dirname(plans_root) }
    let(:order) { Queue.new }
    let(:worktrees) { Dir.mktmpdir("openlanes-wt") }
    let(:executor) do
      sign = ->(agent, dir, round) {
        OpenLanes::Plans::Ledger.append(File.join(dir, agent.ledger.first),
          "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} ]")
      }
      lambda { |agent, subject, root:, round: 1, **|
        order << [agent.name, subject.status.key, File.directory?(root)]
        dir = subject.feature.path
        File.write(File.join(dir, "spec.md"), "#{spec_body}\n## Research\n\nFound.\n") if agent.name == "leah-researcher"
        File.write(File.join(dir, "plan.md"), "") if agent.name == "yoda-writer"
        sleep(0.2)
        sign.call(agent, dir, round)
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
    end

    def git(*) = system("git", "-C", repo, *, out: File::NULL, err: File::NULL)

    def run_in_worktrees
      [stamp, order]
      OpenLanes::Engine::Runner.new(tree:,
        executor:,
        agents:    agents.only("leah-researcher", "yoda-writer"),
        isolation: :worktree,
        jobs:      2,
        worktree:  OpenLanes::Vcs::Worktree.new(root: repo, dir: worktrees, user: "tester", seeder: nil),
        state:,
        sleeper:   ->(_) { sleep(0.02) }).call
    end

    before do
      plans { |t| t.plan "040.00", :new, "minesweeper", files: { "spec.md" => spec_body } }
      git("init", "-q", "--initial-branch=main")
      git("config", "user.email", "ada@example.com")
      git("config", "user.name", "Ada")
      File.write(File.join(repo, "README.md"), "# trial\n")
      git("add", "README.md")
      git("commit", "-qm", "initial")
    end

    after { FileUtils.rm_rf(worktrees) }

    shared_examples "a chain that moves the folder" do
      it "runs leah then yoda, each from the state it handles, and leaves the plan 🔗" do
        attempts = run_in_worktrees
        seen = Array.new(order.size) { order.pop }
        aggregate_failures do
          expect(seen).to eq([["leah-researcher", :new, true], ["yoda-writer", :researched, true]])
          expect(attempts.map { [it.from, it.to] }).to eq([%i[new researched], %i[researched ready_for_linking]])
          expect(tree.reload.subjects.first.status.key).to eq(:ready_for_linking)
        end
      end
    end

    context "with .plans untracked" do
      it_behaves_like "a chain that moves the folder"
    end

    context "with .plans committed" do
      before do
        git("add", ".plans")
        git("commit", "-qm", "plans")
      end

      it_behaves_like "a chain that moves the folder"
    end

    # What a publish leaves in the worktree is a snapshot. A stale one
    # claiming the plan is further on must not steer the run, nor be touched.
    context "with a stale snapshot of the plan in its worktree" do
      let(:stale) do
        feature = tree.reload.subjects.first.feature
        path = OpenLanes::Vcs::Worktree.new(root: repo, dir: worktrees, user: "tester", seeder: nil).checkout_for(feature).path
        File.join(path, ".plans", "040.00━━🟢━━❯minesweeper")
      end

      before do
        FileUtils.mkdir_p(stale)
        File.write(File.join(stale, "spec.md"), "stale\n")
      end

      it_behaves_like "a chain that moves the folder"

      it "leaves the snapshot alone" do
        run_in_worktrees
        expect(Dir.children(stale)).to eq(["spec.md"])
      end
    end
  end

  # 📋 reads only a blank plan.md, so a linker that wrote nothing used to
  # pass straight on to the planner with "work verified on disk".
  describe "an ewoki-linker that never answers depends_on" do
    let!(:built) { plans { |t| t.plan "032.00", :ready_for_linking, "unlinked", files: { "spec.md" => spec_body, "plan.md" => "" } } }
    let(:plan) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("032.00")) }

    def run_linker(result)
      executor = lambda { |agent, subject, round: 1, **|
        calls << agent.name
        if result.ok
          OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, agent.ledger.first),
            "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} ]")
        end
        result
      }
      runner_with(executor, agents: agents.only("ewoki-linker", "luthen-rael-planner"), rounds: 1).call
    end

    it "stays at 🔗 when it signs Completed but its Edit did not land" do
      run_linker(OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0))
      expect([plan.status.key, calls.uniq]).to eq([:ready_for_linking, ["ewoki-linker"]])
    end

    it "stays at 🔗 when it times out" do
      run_linker(OpenLanes::Execution::Executor::Result.new(ok: false, note: "timed out after 900s", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 900.0))
      expect([plan.status.key, calls.uniq]).to eq([:ready_for_linking, ["ewoki-linker"]])
    end
  end

  describe "a Completed the folder cannot honour" do
    let!(:built) { plans { |t| t.plan "031.00", :new, "unresearched", files: { "spec.md" => spec_body } } }
    let(:plan) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("031.00")) }

    # leah signs and names yoda, but writes no `## Research` chapter.
    let!(:attempts) do
      [calls, stamp]
      handoff = OpenLanes::Plans::Ledger.render_handoff(OpenLanes::Plans::Ledger::Handoff.new(at: Time.now, next: "yoda-writer", file: "", line: 0))
      executor = lambda { |agent, subject, round: 1, **|
        calls << agent.name
        OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, agent.ledger.first),
          "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} ]",
          handoff)
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
      runner_with(executor, agents: agents.only("leah-researcher", "yoda-writer"), rounds: 1).call
    end

    it "keeps the folder, hands off to nobody, and records the round as Interrupted" do
      stage = OpenLanes::Plans::PlanState.for(plan.feature.path).stages.last
      aggregate_failures do
        expect(plan.status.key).to eq(:new)
        expect(calls).to eq(["leah-researcher"])
        expect(attempts.first).to have_attributes(ok: false, status: "Interrupted")
        expect(attempts.first.note).to include("Researched is not justified")
        expect(stage).to include("status" => "Interrupted", "to" => "new")
        expect(state.stages("031.00").last).to include("status" => "Interrupted")
      end
    end
  end

  describe "the 020.00 regression" do
    let!(:built) do
      plans { |t| t.plan "020.00", :researched, "qualified-at", files: { "spec.md" => "#{spec_body}\n## Research\n\nFound.\n" } }
    end

    # yoda finishes, leaves a blank plan.md, signs Completed and names
    # luthen-rael. The harness renames to 🔗, ewoki-linker signs, the harness
    # renames to 📋, starts luthen-rael, luthen-rael
    # writes a plan and signs, the harness renames to ⭐, luke and rey
    # start. Nobody is invoked twice and the run does not exit green with
    # the plan unmoved.
    it "moves yoda's finished work through 🔗 to 📋 and starts luthen-rael, then the pair" do
      executor = executor_with do |agent, subject, _round|
        case agent.name
        when "yoda-writer"
          File.write(File.join(subject.feature.path, "plan.md"), "")
          "Completed"
        when "ewoki-linker" then link(subject) && "Completed"
        when "luthen-rael-planner"
          File.write(File.join(subject.feature.path, "plan.md"), "# Plan\n\n## Unit 1\n")
          File.write(File.join(subject.feature.path, "plan-frontend.md"), "# Front end\n\n## F1\n")
          "Completed"
        end
      end
      runner_with(executor).call

      aggregate_failures do
        expect(calls.map(&:first)).to eq(%w[yoda-writer ewoki-linker luthen-rael-planner luke-backend rey-frontend])
        expect(calls.count { |name, _, _| name == "yoda-writer" }).to eq(1)
        expect(tree.reload.find(OpenLanes::Plans::Ordinal.parse("020.00")).status.key).to eq(:building)
      end
    end

    context "when the spec says how the task is finished" do
      let!(:built) do
        frontmatter = "---\ntask-completed-when: it works\nhow-to-verify: run it\n---\n"
        plans do |t|
          t.plan "020.00", :researched, "qualified-at", files: { "spec.md" => "#{frontmatter}#{spec_body}\n## Research\n\nFound.\n" }
        end
      end

      it "copies both lists into the plan the planner wrote, once" do
        executor = executor_with do |agent, subject, _round|
          case agent.name
          when "yoda-writer" then File.write(File.join(subject.feature.path, "plan.md"), "") && "Completed"
          when "ewoki-linker" then link(subject) && "Completed"
          when "luthen-rael-planner" then File.write(File.join(subject.feature.path, "plan.md"), "# Plan\n\n## Unit 1\n") && "Completed"
          end
        end
        runner_with(executor).call
        text = File.read(File.join(path_of("020.00"), "plan.md"))
        expect(text.scan("## Task completed when").size).to eq(1)
        expect(text).to include("- it works", "## How to test", "- run it")
      end
    end

    it "records each promotion on the attempt that earned it" do
      executor = executor_with do |agent, subject, _|
        File.write(File.join(subject.feature.path, "plan.md"), "") if agent.name == "yoda-writer"
        agent.name == "yoda-writer" ? "Completed" : nil
      end
      attempts = runner_with(executor).call
      yoda = attempts.find { |a| a.agent == "yoda-writer" }
      expect([yoda.from, yoda.to]).to eq(%i[researched ready_for_linking])
    end

    context "when a row is running" do
      subject(:row) { dispatcher.board.rows.find(&:running?) }

      let(:dispatcher) { described_class.new(runner: runner_with(executor_with { |*| nil }), sleeper: ->(_) {}) }

      before do
        allow(OpenLanes::UI).to receive(:monotonic).and_return(1000.0)
        dispatcher.tick # dispatches whatever the fixture tree makes eligible
        allow(OpenLanes::UI).to receive(:monotonic).and_return(1042.0)
      end

      # The tick started real agent threads that write ledger lines into the
      # fixture tree; the tree is deleted after the example, so wait for them.
      after { dispatcher.running.each { |job| job.thread.join(5) } }

      it("carries elapsed seconds") { expect(row.elapsed).to eq(42) }
      it("carries the live sub-agent count") { expect(row.subagents).to eq(0) }
    end

    # What `run --scroll-height` draws: every distinct status, newest
    # first, on the running row and on the finished one it leaves behind.
    describe "the agent's statuses, newest first, repeats dropped" do
      # The executor runs on a dispatcher thread: `said` tells the example
      # the statuses are out, `release` lets the agent finish. Both pops time
      # out, so a queue nobody feeds can never hang the suite.
      let(:said) { Queue.new }
      let(:release) { Queue.new }
      let(:executor) do
        said_queue, release_queue = said, release
        lambda { |_agent, _subject, **, &progress|
          ["reading spec.md", "reading spec.md", "editing plan.md"].each do |activity|
            progress.call(OpenLanes::Execution::Transcript::Progress.new(activity:,
              up: 1,
              down: 1,
              subagents: 1,
              running: ["Explore"]))
          end
          said_queue << true
          release_queue.pop(timeout: 5)
          OpenLanes::Execution::Executor::Result.new(ok: false, note: "stopped early", up: 1, down: 1, subagents: 0, delegated: 0, seconds: 1.0)
        }
      end
      let(:dispatcher) { described_class.new(runner: runner_with(executor), sleeper: ->(_) {}) }
      let(:running_key) { dispatcher.board.rows.find(&:running?).key }
      let(:row) { dispatcher.board.rows.find { |r| r.key == running_key } }

      before do
        dispatcher.tick
        said.pop(timeout: 5)
        running_key
      end

      after do
        10.times { release << true }
        dispatcher.running.each { |job| job.thread.join(5) }
      end

      context "when the agent is still running" do
        it { expect(row.history).to eq(["editing plan.md", "reading spec.md"]) }
        it("carries the sub-agents it has running") { expect(row.running).to eq(["Explore"]) }
      end

      context "when the agent is done" do
        before do
          10.times { release << true }
          200.times do
            dispatcher.tick
            break if dispatcher.board.rows.none?(&:running?)

            sleep 0.01
          end
        end

        it("keeps the statuses under the outcome") { expect(row.history.drop(1)).to eq(["editing plan.md", "reading spec.md"]) }
        it("puts the outcome on top") { expect(row.history.first).to eq(row.message) }
        it("leaves no sub-agent running") { expect(row.running).to eq([]) }
      end
    end
  end

  # The 001.00 transcript, the other way round: a folder still named ⚪
  # whose spec.md carries its research and whose plan.md already holds work
  # units. The old loop read the name, offered it to leah-researcher, and
  # she researched a plan that was ready to build.
  describe "a folder whose name lags its contents" do
    let!(:built) do
      plans do |t|
        t.plan "001.00",
          :new,
          "already-planned",
          files: { "spec.md"          => "#{spec_body}\n## Research\n\nWhat was found.\n",
                   "plan.md"          => "# P\n\n## Unit 1\n",
                   "plan-frontend.md" => "# Front end\n\n## F1\n" }
      end
    end

    it "renames it first and offers it to the pair, never to leah-researcher" do
      runner_with(executor_with { |*| nil }).call

      aggregate_failures do
        expect(calls.map(&:first)).not_to include("leah-researcher")
        expect(calls.map(&:first).first(2)).to contain_exactly("luke-backend", "rey-frontend")
      end
    end

    it "previews the same pair on a dry run, and renames nothing" do
      runner_with(executor_with { |*| nil }, dry_run: true).call

      aggregate_failures do
        expect(calls.map(&:first)).to contain_exactly("luke-backend", "rey-frontend")
        expect(Dir.children(plans_root)).to include("001.00━━⚪━━❯already-planned")
      end
    end
  end

  describe "pairing" do
    let!(:built) do
      plans do |t|
        t.plan "000.00", :new, "alone", files: { "spec.md" => spec_body }
        t.plan "001.00", :building, "paired", files: { "spec.md" => spec_body, "plan.md" => "# P", "plan-frontend.md" => "## F1" }
      end
    end

    # The executor puts the partner's name and the mailbox into the prompt.
    # It can only do that if the dispatch tells it who the partner is.
    it "tells each half of a pair who its partner is, and a lone agent nothing" do
      seen = {}
      executor = lambda { |agent, subject, partners: [], **|
        seen[[agent.name, subject.feature.ordinal.to_s]] = partners.map(&:name)
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "noop", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
      runner_with(executor).call

      expect(seen).to eq(
        ["leah-researcher", "000.00"] => [],
        ["luke-backend", "001.00"]    => ["rey-frontend"],
        ["rey-frontend", "001.00"]    => ["luke-backend"]
      )
    end
  end

  describe "routing" do
    let(:seen) { [] }
    let(:executor) do
      lambda { |agent, subject, **|
        seen << [agent.name, subject.feature.ordinal.to_s]
        link(subject) if agent.name == "ewoki-linker"
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "noop", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
    end

    context "when the plan has no front-end units" do
      let!(:built) do
        plans do |t|
          t.plan "001.00",
            :planned,
            "backend-only",
            files: { "spec.md" => spec_body, "plan.md" => "# P\n\n## U1\n", "plan-frontend.md" => "# Front end\n\nNone.\n" }
        end
      end

      it "starts luke-backend alone" do
        runner_with(executor).call
        expect(seen.map(&:first).uniq).to eq(%w[luke-backend])
      end
    end

    context "when spec.md switches the front end off" do
      let!(:built) do
        plans do |t|
          t.plan "001.00",
            :planned,
            "no-ui",
            files: { "spec.md" => "---\nfrontend: false\n---\n#{spec_body}", "plan.md" => "# P\n\n## U1\n",
                     "plan-frontend.md" => "## F1\n" }
        end
      end

      it "never starts rey-frontend, units or not" do
        runner_with(executor).call
        expect(seen.map(&:first).uniq).to eq(%w[luke-backend])
      end
    end

    context "when spec.md forces the front end on" do
      let!(:built) do
        plans do |t|
          t.plan "001.00",
            :planned,
            "ui",
            files: { "spec.md" => "---\nfrontend: true\n---\n#{spec_body}", "plan.md" => "# P\n\n## U1\n" }
        end
      end

      it "starts the pair without a plan-frontend.md" do
        runner_with(executor).call
        expect(seen.map(&:first).uniq).to contain_exactly("luke-backend", "rey-frontend")
      end
    end

    context "with a 🔗 plan whose spec already answers depends_on" do
      let!(:built) do
        plans do |t|
          t.plan "001.00", :ready_for_linking, "known", files: { "spec.md" => "---\ndepends_on: [none]\n---\n#{spec_body}", "plan.md" => "" }
        end
      end

      it "never invokes ewoki-linker, and hands the plan to the planner" do
        runner_with(executor).call
        expect(seen.map(&:first)).not_to include("ewoki-linker")
        expect(seen.map(&:first).first).to eq("luthen-rael-planner")
      end
    end

    context "with the plan lane" do
      let!(:built) do
        plans { |t| t.plan "001.00", :new, "known", files: { "spec.md" => "---\nlane: plan\n---\n#{spec_body}" } }
      end

      it "skips research and rewriting, links, and goes to the planner" do
        runner_with(executor).call
        expect(seen.map(&:first).first(2)).to eq(%w[ewoki-linker luthen-rael-planner])
      end

      it "leaves the blank plan.md the planner expects, under the 📋 name" do
        runner_with(executor).call
        expect(tree.reload.subjects.first.status.key).to eq(:ready_for_planning)
      end
    end

    context "with the quick lane" do
      let!(:built) do
        plans do |t|
          t.plan "001.00", :new, "split-migration", files: { "spec.md" => "---\nlane: quick\n---\n#{spec_body}" }
        end
      end

      it "links the plan, then hands it straight to r2d2-mechanic" do
        runner_with(executor).call
        expect(seen.map(&:first).uniq).to eq(%w[ewoki-linker r2d2-mechanic])
      end

      it "writes a one-unit plan.md so the folder may claim ⭐ and then 🟡" do
        runner_with(executor).call
        expect(tree.reload.subjects.first.read("plan.md")).to include("## Task")
      end
    end

    context "with the quick lane on a dry run" do
      let!(:built) do
        plans do |t|
          t.plan "001.00", :new, "split-migration", files: { "spec.md" => "---\nlane: quick\n---\n#{spec_body}" }
        end
      end

      it "previews ewoki-linker, the lane's first agent, and writes nothing" do
        runner_with(executor, dry_run: true).call
        expect([seen.map(&:first).uniq, tree.reload.subjects.first.read("plan.md")]).to eq([%w[ewoki-linker], nil])
      end
    end
  end

  describe "state.json" do
    let!(:built) do
      plans { |t| t.plan "001.00", :new, "fresh", files: { "spec.md" => spec_body } }
    end
    let(:plan_state) { OpenLanes::Plans::PlanState.for(path_of("001.00")) }

    context "when an agent signs through `openlanes state sign`" do
      let(:executor) do
        lambda { |agent, subject, round: 1, **|
          calls << [agent.name, subject.feature.ordinal.to_s, round]
          if agent.name == "leah-researcher"
            File.write(File.join(subject.feature.path, "spec.md"), "#{spec_body}\n## Research\n\nFound it.\n")
            OpenLanes::Plans::PlanState.for(subject.feature.path).sign!(agent: agent.name, round:, status: "Completed")
          end
          OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 10, down: 2, subagents: 0, delegated: 0, seconds: 1.0)
        }
      end

      before { runner_with(executor, agents: agents.only("leah-researcher")).call }

      it "settles the round from the JSON signature alone" do
        expect(tree.reload.subjects.first.status.key).to eq(:researched)
      end

      it "records the stage, with its outcome and spend" do
        expect(plan_state.stages.first.values_at("agent", "round", "status", "from", "to", "up"))
          .to eq(["leah-researcher", 1, "Completed", "new", "researched", 10])
      end

      it "records the state the folder moved to" do
        expect(plan_state.state).to eq("researched")
      end
    end

    context "when a dead harness left a stage Started" do
      before do
        OpenLanes::Plans::PlanState.for(path_of("001.00"))
                                   .stage!(agent: "leah-researcher", round: 1, status: "Started", run: { "pid" => 999_999, "host" => Socket.gethostname })
        runner_with(executor_with { |*| nil }, agents: agents.only("leah-researcher"), state: nil).call
      end

      it "marks it Interrupted, and says the harness died" do
        expect(plan_state.stages.find { |s| s["round"] == 1 }.values_at("status", "note")).to eq(["Interrupted", "harness died"])
      end

      it "signs the harness's Interrupted in state.json, not in the agent's document" do
        aggregate_failures do
          expect(signed("001.00")).to include(["Interrupted", 1, "harness died"])
          expect(File.read(File.join(path_of("001.00"), "spec.md"))).not_to include("Interrupted")
        end
      end

      it "starts the agent again on the same round, since the harness died and not the agent" do
        expect(calls).to eq([["leah-researcher", "001.00", 1]])
      end

      it "mails the agent to carry on from its resume note" do
        mail = OpenLanes::Plans::Mailbox.new(dir: path_of("001.00")).for("leah-researcher")
        expect(mail.map { [it.from, it.body] }).to match([["openlanes", start_with("RESUME: the harness died during your round 1")]])
      end
    end
  end

  # luke finished and left the plan at 🎨; rey died before signing. Rey
  # resumes it, and still hears from luke through the mailbox.
  describe "a plan held at Building UI" do
    let!(:built) do
      plans { |t| t.plan "001.00", :building_ui, "held", files: { "spec.md" => spec_body, "plan.md" => "# P" } }
    end

    it "goes back to rey, with luke named as the partner" do
      seen = {}
      executor = lambda { |agent, _subject, partners: [], **|
        seen[agent.name] = partners.map(&:name)
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "noop", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
      runner_with(executor).call

      expect(seen).to eq("rey-frontend" => ["luke-backend"])
    end
  end

  describe "handoffs" do
    let!(:built) { plans { |t| t.plan "001.00", :new, "relay", files: { "spec.md" => spec_body } } }

    it "starts the named successor only after the predecessor exited" do
      order = []
      executor = lambda { |agent, subject, round: 1, **|
        order << [:start, agent.name]
        file = File.join(subject.feature.path, "spec.md")
        if agent.name == "leah-researcher"
          File.write(file, "#{spec_body}\n## Research\n\nFound.\n")
          OpenLanes::Plans::Ledger.append(file,
            "> [#{stamp}] [ agent: leah-researcher   status: Completed, round 1 ]",
            "> [#{stamp}] [ next: yoda-writer ]")
        end
        order << [:end, agent.name]
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
      runner_with(executor).call
      expect(order.first(3)).to eq([[:start, "leah-researcher"], [:end, "leah-researcher"], [:start, "yoda-writer"]])
    end

    # hansolo is on the roster, so the refusal is about what he handles and
    # not about whether he exists; nobody left handles 🔎, so the run stops.
    it "refuses a next: that names an agent who does not handle the new state, and says so" do
      executor = lambda { |_agent, subject, round: 1, **|
        file = File.join(subject.feature.path, "spec.md")
        File.write(file, "#{spec_body}\n## Research\n\nFound.\n")
        OpenLanes::Plans::Ledger.append(file,
          "> [#{stamp}] [ agent: leah-researcher   status: Completed, round 1 ]",
          "> [#{stamp}] [ next: hansolo-reviewer ]")
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
      attempts = runner_with(executor, agents: agents.only("leah-researcher", "hansolo-reviewer")).call
      expect(attempts.first.note).to include("next: names hansolo-reviewer", "does not handle")
    end
  end

  describe "outcomes other than Completed" do
    let!(:built) { plans { |t| t.plan "001.00", :new, "again", files: { "spec.md" => spec_body } } }

    it "re-runs an Almost completed agent while it has rounds, then parks the plan" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "leah.md"), "---\nname: leah-researcher\nhandles: [new]\nadvances_to: researched\nrounds: 2\nledger: [spec.md]\n---\nbody")
        two = OpenLanes::Agents::Registry.new(dir:)
        executor = executor_with { |_, _, _| "Almost completed" }
        attempts = OpenLanes::Engine::Runner.new(tree:,
          executor:,
          agents: two,
          isolation: :shared,
          jobs: 1,
          state:,
          sleeper: ->(_) {},
          extensions: limits).call
        aggregate_failures do
          expect(calls.map(&:last)).to eq([1, 2])
          expect(attempts.last.note).to include("no rounds left")
        end
      end
    end

    # E1: on a run nobody can answer, an agent out of rounds is given one
    # more on its own, once, with the request it asked on record.
    it "gives an agent out of rounds one more on its own when nobody can answer, and then parks the plan" do
      executor = executor_with { |_, _, _| "Almost completed" }
      attempts = runner_with(executor,
        agents:     agents.only("leah-researcher"),
        extensions: OpenLanes::Engine::Extensions.new(stay: false)).call
      requests = OpenLanes::Plans::PlanState.for(path_of("001.00")).extensions
      aggregate_failures do
        expect(calls.map(&:last)).to eq([1, 2])
        expect(attempts.last.note).to include("no rounds left")
        expect(requests.first).to include("limit" => "rounds", "by" => "auto", "grant" => "round")
        expect(requests.last).to include("round" => 2).and(satisfy { !it.key?("settled_at") })
      end
    end

    it "starts a round a person gave twenty minutes with them on its clock" do
      seen = []
      executor = lambda { |agent, subject, round: 1, handle: nil, **|
        handle.clock = OpenLanes::Execution::Clock.new(seconds: 60, control: File.join(subject.feature.path, "c"), on_expire: -> {}, now: -> { 0 })
        seen << handle.remaining
        calls << [agent.name, subject.feature.ordinal.to_s, round]
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
      plan = OpenLanes::Plans::PlanState.for(path_of("001.00"))
      plan.ask_extension!(agent: "leah-researcher", state: :new, round: 1, limit: "rounds")
      limits.answer!(path_of("001.00"), 1, "c", by: "dana")
      runner_with(executor, agents: agents.only("leah-researcher")).call
      expect(seen.first).to eq(1260)
    end

    it "never re-runs a Completed agent whose promotion was refused, and reports the refusal" do
      executor = executor_with { |_, _, _| "Completed" } # no Research chapter written
      attempts = runner_with(executor, agents: agents.only("leah-researcher")).call
      aggregate_failures do
        expect(calls.size).to eq(1)
        expect(attempts.first.ok).to be(false)
        expect(attempts.first.note).to include("Researched", "no `## Research` chapter")
      end
    end

    it "parks a Blocked plan at ⭕ when blocked.md names a question" do
      executor = executor_with do |_, subject, _|
        File.write(File.join(subject.feature.path, "blocked.md"), "## B1\n\nWhich?\n")
        "Blocked"
      end
      runner_with(executor, agents: agents.only("leah-researcher")).call
      expect(tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).status.key).to eq(:blocked)
    end

    it "parks a product block at 🛑 when the note says so" do
      executor = lambda { |_agent, subject, round: 1, **|
        File.write(File.join(subject.feature.path, "blocked.md"), "## B1\n\nWhich colour?\n")
        OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, "spec.md"),
          "> [#{stamp}] [ agent: leah-researcher   status: Blocked, round 1 (product) ]")
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
      runner_with(executor, agents: agents.only("leah-researcher")).call
      expect(tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).status.key).to eq(:product_blocked)
    end
  end

  describe "the plan lock" do
    let!(:built) { plans { |t| t.plan "001.00", :new, "locked", files: { "spec.md" => spec_body } } }
    let(:seen) { [] }

    it "holds locked-by.pid while the agent works, and drops it after" do
      executor = executor_with do |_, subject, _|
        seen << [OpenLanes::Plans::Lock.read(subject.feature.path), File.basename(subject.feature.path)]
        "Almost completed"
      end
      runner_with(executor, agents: agents.only("leah-researcher")).call

      aggregate_failures do
        expect(seen.first.first).to have_attributes(pid: Process.pid, host: Socket.gethostname)
        expect(seen.map(&:last).uniq).to eq(["001.00━━⚪━━❯locked"])
        expect(Dir.glob(File.join(plans_root, "**", OpenLanes::Plans::Lock::FILENAME))).to be_empty
      end
    end

    it "drops the lock when the agent raises" do
      executor = lambda { |_agent, subject, **|
        seen << OpenLanes::Plans::Lock.read(subject.feature.path)
        raise "the agent fell over"
      }
      runner_with(executor, agents: agents.only("leah-researcher")).call

      aggregate_failures do
        expect(seen.first).not_to be_nil
        expect(Dir.glob(File.join(plans_root, "**", OpenLanes::Plans::Lock::FILENAME))).to be_empty
      end
    end

    # Another run's lock keeps this one out entirely: no agent, and no
    # start-time rename under the holder's feet.
    {
      "a live process on this host" => -> { { "pid" => Process.ppid, "host" => Socket.gethostname } },
      "a process on another host"   => -> { { "pid" => 1, "host" => "elsewhere.invalid" } }
    }.each do |holder, data|
      it "neither dispatches nor renames a plan locked by #{holder}" do
        File.write(File.join(path_of("001.00"), OpenLanes::Plans::Lock::FILENAME),
          JSON.generate(data.call.merge("started_at" => "2026-10-13T09:00:00Z")))
        runner_with(executor_with { "Almost completed" }, agents: agents.only("leah-researcher")).call

        aggregate_failures do
          expect(calls).to be_empty
          expect(File.basename(path_of("001.00"))).to eq("001.00━━⚪━━❯locked")
          expect(OpenLanes::Plans::Lock.read(path_of("001.00")).pid).to eq(data.call["pid"])
        end
      end
    end

    # Two runs both saw no lock; the other wrote first. The claim is the
    # check, so this run starts nothing and records nothing as started.
    it "starts nothing when another run takes the lock between the check and the claim" do
      File.write(File.join(path_of("001.00"), OpenLanes::Plans::Lock::FILENAME),
        JSON.generate("pid" => Process.ppid, "host" => Socket.gethostname, "started_at" => "2026-10-13T09:00:00Z"))
      lost = false
      allow(OpenLanes::Plans::Lock).to receive(:write).and_wrap_original do |original, *args, **opts|
        original.call(*args, **opts)
      rescue OpenLanes::Plans::Lock::Held
        lost = true
        raise
      end
      runner_with(executor_with { "Almost completed" }, agents: agents.only("leah-researcher")).call do |dispatcher|
        # The check misses the lock until the claim has been refused once.
        allow(dispatcher).to(receive(:locked_elsewhere?).and_wrap_original { |m, subject| lost && m.call(subject) })
      end

      aggregate_failures do
        expect(calls).to be_empty
        expect(OpenLanes::Plans::Lock.read(path_of("001.00")).pid).to eq(Process.ppid)
        expect(File.read(File.join(path_of("001.00"), "spec.md"))).not_to include("status: Started")
      end
    end

    it "dispatches over a stale lock left by a dead process on this host" do
      pid = Process.spawn("true")
      Process.wait(pid)
      File.write(File.join(path_of("001.00"), OpenLanes::Plans::Lock::FILENAME),
        JSON.generate("pid" => pid, "host" => Socket.gethostname, "started_at" => "2026-10-13T09:00:00Z"))
      runner_with(executor_with { "Almost completed" }, agents: agents.only("leah-researcher")).call

      expect(calls.map(&:first)).to eq(["leah-researcher"])
    end

    it "writes no lock on a dry run" do
      executor = executor_with do |_, subject, _|
        seen << OpenLanes::Plans::Lock.read(subject.feature.path)
        "Almost completed"
      end
      runner_with(executor, agents: agents.only("leah-researcher"), dry_run: true).call

      expect(seen).to eq([nil])
    end
  end

  describe "verify and sign" do
    let!(:built) { plans { |t| t.plan "001.00", :new, "cut-off", files: { "spec.md" => spec_body } } }

    # The agent did the work and was killed before its closing line. The
    # invariant of 🔎 holds, so the harness signs on its behalf, in state.json,
    # and the plan moves.
    it "signs Completed for a killed agent whose work is on disk" do
      executor = lambda { |_agent, subject, round: 1, **|
        file = File.join(subject.feature.path, "spec.md")
        File.write(file, "#{spec_body}\n## Research\n\nFound.\n")
        OpenLanes::Plans::Ledger.append(file, "> [#{stamp}] [ agent: leah-researcher   status: Started, round 1 ]")
        OpenLanes::Execution::Executor::Result.new(ok: false, note: "killed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0, killed: :key)
      }
      attempts = runner_with(executor, agents: agents.only("leah-researcher")).call
      text = File.read(File.join(path_of("001.00"), "spec.md"))
      aggregate_failures do
        expect(signed("001.00")).to include(["Interrupted", 1, "killed by harness after 15s grace"],
          ["Completed", 1, "signed by harness: work verified on disk"])
        expect(text).not_to include("signed by harness")
        expect(tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).status.key).to eq(:researched)
        expect(attempts.first.to).to eq(:researched)
      end
    end

    it "writes only Interrupted, and re-runs, when the work is not there" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "leah.md"), "---\nname: leah-researcher\nhandles: [new]\nadvances_to: researched\nrounds: 2\nledger: [spec.md]\n---\nbody")
        two = OpenLanes::Agents::Registry.new(dir:)
        executor = lambda { |_agent, _subject, round: 1, **|
          calls << round
          OpenLanes::Execution::Executor::Result.new(ok: false, note: "timed out", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0, killed: :timeout)
        }
        OpenLanes::Engine::Runner.new(tree:,
          executor:,
          agents: two,
          isolation: :shared,
          jobs: 1,
          state:,
          sleeper: ->(_) {},
          extensions: limits).call
        text = File.read(File.join(path_of("001.00"), "spec.md"))
        aggregate_failures do
          expect(calls).to eq([1, 2])
          expect(signed("001.00").map(&:first)).to eq(%w[Interrupted Interrupted])
          expect(text).not_to include("Interrupted")
        end
      end
    end
  end

  describe "the pair" do
    # 🟢 Ready for Review needs an open pull request recorded. A real run has
    # the publisher write that row; this example has no publisher, so the
    # fixture carries it from the start.
    let!(:built) do
      plans { |t|
        t.plan "001.00",
          :planned,
          "both",
          files: { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## U1\n", "plan-frontend.md" => "## F1\n" },
          prs:   [t.open(7, "[001.00](A) Both")]
      }
    end

    # Two doubles share one folder here, which a real run never allows
    # (shared isolation is serial), so they keep out of each other's way:
    # one signs at a time, and luke does not return until rey has signed,
    # so rey's line is on disk before the fold to 🎨 moves the folder.
    it "renames to 🟡 when luke starts, holds at 🎨 when luke finishes first, and goes 🟢 when rey does" do
      seen = []
      signing = Mutex.new
      rey_signed = Queue.new
      executor = lambda { |agent, subject, round: 1, **|
        seen << [agent.name, subject.status.key]
        file = File.join(subject.feature.path, "pull-requests.md")
        signing.synchronize do
          OpenLanes::Plans::Ledger.append(file, "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round 1 ]")
        end
        if agent.name == "rey-frontend"
          rey_signed << true
          sleep(0.2) # rey takes longer, so luke completes while rey is still running
        else
          rey_signed.pop
        end
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
      runner = OpenLanes::Engine::Runner.new(tree:,
        executor:,
        agents: agents.only("luke-backend", "rey-frontend"),
        isolation: :shared,
        jobs: 2,
        state:,
        sleeper: ->(_s) { sleep(0.05) })
      allow(runner).to receive(:jobs).and_return(2) # let two run at once without a worktree
      runner.call
      aggregate_failures do
        expect(seen.map(&:last)).to eq(%i[building building])
        expect(tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).status.key).to eq(:ready_for_review)
      end
    end
  end

  describe "a build finished in a run that opens no pull request" do
    let!(:built) do
      plans do |t|
        t.plan "001.00", :new, "tic-tac-toe", files: { "spec.md" => "---\nlane: quick\ndepends_on: [none]\n---\n#{spec_body}" }
      end
    end

    let(:status) { tree.reload.subjects.first.status.key }

    # The executor reads these from the agent's thread. Memoized first, here,
    # so it does not wait on the let! below, which holds RSpec's memo lock
    # for as long as the run takes.
    before { [calls, stamp] }

    context "when the builder signs Completed" do
      let!(:attempts) { runner_with(executor_with { |_, _, _| "Completed" }, agents: agents.only("r2d2-mechanic")).call }

      it "stays at 🟡, done for this run, and says it waits for a pull request" do
        aggregate_failures do
          expect(status).to eq(:building)
          expect(attempts.map(&:ok)).to eq([true])
          expect(attempts.first.note).to include("built locally, no pull request in this run")
        end
      end
    end

    context "when the build leaves the plan without its spec" do
      let!(:attempts) do
        careless = executor_with do |_agent, subject, _round|
          File.delete(File.join(subject.feature.path, "spec.md"))
          "Completed"
        end
        runner_with(careless, agents: agents.only("r2d2-mechanic")).call
      end

      it "reports the missing file instead of parking the plan as built" do
        aggregate_failures do
          expect(attempts.first.ok).to be(false)
          expect(attempts.first.note).to include("`spec.md`")
        end
      end
    end

    context "when the builder's note says approved" do
      let!(:attempts) do
        approving = executor_with do |agent, subject, round|
          OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, agent.ledger.first),
            "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} (approved) ]")
          nil
        end
        runner_with(approving, agents: agents.only("r2d2-mechanic")).call
      end

      it "is not taken as a review verdict" do
        aggregate_failures do
          expect(status).to eq(:building)
          expect(attempts.first.note).not_to include("awaiting merge")
          expect(attempts.first.note).to include("built locally")
        end
      end
    end
  end

  # A worktree run with a publisher: the run every real build takes. The
  # publisher is a double, so nothing reaches the network; the checkout is a
  # double, so no `git worktree add` runs.
  describe "a build finished in a run that publishes" do
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
    let(:plan) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")) }
    let(:files) do
      { "spec.md" => "---\nlane: quick\n---\n#{spec_body}", "plan.md" => "# Plan\n\n## U1\n", "pull-requests.md" => "# Pull Requests\n" }
    end
    let!(:built) { plans { |t| t.plan "001.00", :building, "tic-tac-toe", files: } }
    let(:roster) { agents.only("r2d2-mechanic") }
    let(:attempts) do
      OpenLanes::Engine::Runner.new(tree:,
        executor:,
        agents: roster,
        isolation: :worktree,
        jobs: 1,
        worktree:,
        publisher:,
        state:,
        # No round granted on its own (E1), so each example counts only the rounds it asks for.
        extensions: limits,
        sleeper: ->(_) {}).call
    end
    let(:executor) do
      executor_with do |agent, subject, round|
        next "Completed" unless agent.name == "hansolo-reviewer"

        OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, agent.ledger.first),
          "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} (approved) ]")
        nil
      end
    end

    before do
      [calls, stamp]
      allow(publisher).to receive(:publish).and_return(publication)
    end

    context "when a builder signs Completed on its first build" do
      before { attempts }

      it "publishes, records the pull request, and moves the folder to 🟢" do
        aggregate_failures do
          expect(publisher).to have_received(:publish).once
          expect(plan.pull_requests.map(&:url)).to eq([url])
          expect(plan.status.key).to eq(:ready_for_review)
          expect(attempts.first).to have_attributes(ok: true, to: :ready_for_review)
          expect(attempts.first.note).to include("opened #{url}")
        end
      end
    end

    context "when the reviewer approves with a note that mentions rejecting" do
      let(:roster) { agents.only("r2d2-mechanic", "hansolo-reviewer") }
      let(:executor) do
        executor_with do |agent, subject, round|
          next "Completed" unless agent.name == "hansolo-reviewer"

          OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, agent.ledger.first),
            "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} (approved, nothing to reject) ]")
          nil
        end
      end

      before { attempts }

      it "reads the verdict from the note's leading word and leaves the plan at 👀" do
        expect(plan.status.key).to eq(:in_review)
      end
    end

    context "when the reviewer follows in the same run" do
      let(:roster) { agents.only("r2d2-mechanic", "hansolo-reviewer") }

      before { attempts }

      it "hands the 🟢 plan to hansolo, whose approval leaves it at 👀" do
        aggregate_failures do
          expect(attempts.map(&:agent)).to eq(%w[r2d2-mechanic hansolo-reviewer])
          expect(plan.status.key).to eq(:in_review)
        end
      end
    end

    context "when publishing is refused" do
      let(:publication) do
        OpenLanes::Vcs::Publisher::Publication.new(ordinal: OpenLanes::Plans::Ordinal.parse("001.00"),
          branch: checkout.branch,
          title: "[001.00](A) Tic Tac Toe",
          url: nil,
          refusal: "push rejected")
      end

      before { attempts }

      it "stays at 🟡, fails the attempt with the reason, and does not run the builder again" do
        aggregate_failures do
          expect(plan.status.key).to eq(:building)
          expect(attempts.map(&:ok)).to eq([false])
          expect(attempts.first.note).to include("push rejected")
          expect(calls.size).to eq(1)
        end
      end
    end

    context "when publishing is refused because plan.md says nothing of how to test it" do
      let(:publication) do
        OpenLanes::Vcs::Publisher::Publication.new(ordinal: OpenLanes::Plans::Ordinal.parse("001.00"),
          branch: checkout.branch,
          title: "[001.00](A) Tic Tac Toe",
          url: nil,
          refusal: OpenLanes::Vcs::Publisher::UNTESTABLE)
      end
      let(:mail) { OpenLanes::Plans::Mailbox.new(dir: plan.feature.path).for("r2d2-mechanic") }

      before { attempts }

      it "mails the builder what is missing and runs it once more, then leaves it Interrupted for a person" do
        aggregate_failures do
          expect(plan.status.key).to eq(:building)
          expect(calls.size).to eq(2)
          expect(attempts.map(&:status)).to eq(%w[Interrupted Interrupted])
          expect(attempts.map(&:note)).to match([include("plan.md has no `## How to test` section", "r2d2-mechanic was asked to add it"),
                                                 include("still missing after r2d2-mechanic was asked")])
          expect([mail.size, mail.first.from, mail.first.body]).to match([1, "openlanes", include("Add one to plan.md")])
        end
      end
    end

    # The specs above opt out of E1's automatic round; this one keeps the
    # defaults a real run has, so a change to how #66's hand-back and E1's
    # grant add up shows here as a different count.
    context "when publishing is refused and the run keeps the default extensions" do
      let(:limits) { nil }
      let(:publication) do
        OpenLanes::Vcs::Publisher::Publication.new(ordinal: OpenLanes::Plans::Ordinal.parse("001.00"),
          branch: checkout.branch,
          title: "[001.00](A) Tic Tac Toe",
          url: nil,
          refusal: OpenLanes::Vcs::Publisher::UNTESTABLE)
      end

      before { attempts }

      it "runs the build, the round it is handed back, and the round E1 grants, then waits for a person" do
        aggregate_failures do
          expect(plan.status.key).to eq(:building)
          expect(calls.size).to eq(3)
          expect(attempts.map(&:status)).to eq(%w[Interrupted Interrupted Interrupted])
          expect(attempts.last.note).to include("still missing after r2d2-mechanic was asked")
        end
      end
    end

    context "when the builder adds the missing section after being asked" do
      let(:refused) do
        OpenLanes::Vcs::Publisher::Publication.new(ordinal: OpenLanes::Plans::Ordinal.parse("001.00"),
          branch: checkout.branch,
          title: "[001.00](A) Tic Tac Toe",
          url: nil,
          refusal: OpenLanes::Vcs::Publisher::UNTESTABLE)
      end
      let(:mail) { OpenLanes::Plans::Mailbox.new(dir: plan.feature.path).for("r2d2-mechanic") }

      before do
        allow(publisher).to receive(:publish).and_return(refused, publication)
        attempts
      end

      it "opens the pull request on the second round and mails only once" do
        aggregate_failures do
          expect(calls.size).to eq(2)
          expect(plan.status.key).to eq(:ready_for_review)
          expect(mail.size).to eq(1)
          expect(mail.first.body).to include("every part of the build")
        end
      end
    end

    context "when ready-for-review cannot be applied to the pull request it opened" do
      let(:publication) do
        OpenLanes::Vcs::Publisher::Publication.new(ordinal: OpenLanes::Plans::Ordinal.parse("001.00"),
          branch: checkout.branch,
          title: "[001.00](A) Tic Tac Toe",
          url:,
          refusal: nil,
          label_error: "could not label #12: HTTP 403")
      end

      before { attempts }

      it "still moves to 🟢, and the attempt note says the label is missing" do
        aggregate_failures do
          expect(plan.status.key).to eq(:ready_for_review)
          expect(attempts.first.note).to include("opened #{url}", "ready-for-review not applied: could not label #12: HTTP 403")
        end
      end
    end

    context "when a re-build after 🔴 finds its pull request already open" do
      let!(:built) do
        plans { |t| t.plan "001.00", :rejected, "tic-tac-toe", files: files.except("pull-requests.md"), prs: [t.open(12, "[001.00](A) Tic Tac Toe")] }
      end
      let(:publication) do
        OpenLanes::Vcs::Publisher::Publication.new(ordinal: OpenLanes::Plans::Ordinal.parse("001.00"),
          branch: checkout.branch,
          title: "[001.00](A) Tic Tac Toe",
          url:,
          refusal: nil,
          updated: true)
      end

      before { attempts }

      it "pushes to that pull request and records no second one" do
        aggregate_failures do
          expect(publisher).to have_received(:publish).once
          expect(plan.pull_requests.map(&:number)).to eq(["12"])
          expect(plan.status.key).to eq(:ready_for_review)
          expect(attempts.first.note).to include("pushed to #{url}")
        end
      end
    end
  end

  describe "the reviewer's verdicts" do
    let!(:built) do
      plans { |t|
        t.plan "001.00",
          :ready_for_review,
          "judged",
          files: { "spec.md" => spec_body, "plan.md" => "# P\n\n## U\n" },
          prs:   [t.open(7, "[001.00](A) Judged")]
      }
    end

    def hansolo(note)
      lambda { |_agent, subject, round: 1, **|
        OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, "pull-requests.md"),
          "> [#{stamp}] [ agent: hansolo-reviewer   status: Completed, round #{round} (#{note}) ]")
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
    end

    it "moves a rejection to 🔴" do
      runner_with(hansolo("rejected 1/2"), agents: agents.only("hansolo-reviewer")).call
      expect(tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).status.key).to eq(:rejected)
    end

    it "leaves an approval at 👀 and treats the plan as finished for this run" do
      attempts = runner_with(hansolo("approved"), agents: agents.only("hansolo-reviewer")).call
      aggregate_failures do
        expect(tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).status.key).to eq(:in_review)
        expect(attempts.size).to eq(1)
        expect(attempts.first.note).to include("approved")
      end
    end

    it "records the approval in state.json and keeps the plan on the board, with no cars, past LINGER" do
      dispatcher = described_class.new(runner: runner_with(hansolo("approved"), agents: agents.only("hansolo-reviewer")),
        sleeper: ->(_) {})
      dispatcher.run
      later = OpenLanes::UI.monotonic + described_class::LINGER + 1
      allow(OpenLanes::UI).to receive(:monotonic).and_return(later)
      board = dispatcher.board

      aggregate_failures do
        expect(OpenLanes::Plans::PlanState.for(path_of("001.00")).finished.kind).to eq("approved")
        expect(board.plans).to eq(["001.00"])
        expect(board.rows).to be_empty
      end
    end

    it "forgets the approval once an agent starts on the plan again" do
      OpenLanes::Plans::PlanState.for(path_of("001.00")).finish!("approved")
      dispatcher = described_class.new(runner: runner_with(hansolo("rejected 1/2"), agents: agents.only("hansolo-reviewer")),
        sleeper: ->(_) {})
      dispatcher.run

      expect(OpenLanes::Plans::PlanState.for(path_of("001.00")).finished).to be_nil
    end
  end

  describe "a restarted engine" do
    before do
      plans do |t|
        t.plan "001.00", :approved, "oldest", files: { "spec.md" => spec_body }
        t.plan "002.00", :approved, "latest", files: { "spec.md" => spec_body }
        t.plan "003.00", :in_review, "approved", files: { "spec.md" => spec_body, "plan.md" => "# P\n\n## U\n" }
        t.plan "004.00", :new, "untouched", files: { "spec.md" => spec_body }
      end
      { "001.00" => ["merged", 3], "002.00" => ["merged", 1], "003.00" => ["approved", 2] }.each do |ordinal, (kind, hours)|
        OpenLanes::Plans::PlanState.for(path_of(ordinal)).finish!(kind, at: Time.utc(2026, 10, 18, 12) - (hours * 3600))
      end
    end

    it "carries over only the plan that finished last, whichever way it finished" do
      dispatcher = described_class.new(runner: runner_with(executor_with { |*| nil }, agents: agents.only("hansolo-reviewer")),
        sleeper: ->(_) {})

      expect(dispatcher.board.plans).to eq(["002.00"])
    end
  end

  describe "restarting after a dead harness" do
    let!(:built) { plans { |t| t.plan "001.00", :new, "resumed", files: { "spec.md" => spec_body } } }

    # The stranded round is handed back, so leah still has both of hers.
    it "signs the harness's Interrupted for a stranded stage and re-runs the agent" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "leah.md"), "---\nname: leah-researcher\nhandles: [new]\nadvances_to: researched\nrounds: 2\nledger: [spec.md]\n---\nbody")
        two = OpenLanes::Agents::Registry.new(dir:)
        dead = OpenLanes::Engine::StateFile.new(path: OpenLanes::Engine::StateFile.for(tree), pid: 999_999_999)
        dead.begin_run!(root: File.dirname(plans_root))
        dead.record("001.00", agent: "leah-researcher", round: 1, status: "Started", state: "new")
        dead.save

        executor = executor_with { |_, _, _| nil }
        runner_with(executor, agents: two, state: OpenLanes::Engine::StateFile.new(path: dead.path)).call
        aggregate_failures do
          expect(signed("001.00")).to include(["Interrupted", 1, "harness died"])
          expect(calls.map(&:last)).to eq([1, 2])
          expect(OpenLanes::Plans::PlanState.for(path_of("001.00")).stages.flat_map(&:keys)).not_to include("run")
        end
      end
    end
  end

  describe "a dry run" do
    let!(:built) { plans { |t| t.plan "001.00", :new, "preview", files: { "spec.md" => spec_body } } }

    it "invokes each eligible agent once, writes no ledger, renames nothing, saves no state" do
      executor = OpenLanes::Execution::Executor.new(root: File.dirname(plans_root), dry_run: true)
      attempts = runner_with(executor, dry_run: true).call
      aggregate_failures do
        expect(attempts.map(&:agent)).to eq(%w[leah-researcher])
        expect(File.read(File.join(path_of("001.00"), "spec.md"))).not_to include("[ agent:")
        expect(File).not_to exist(state.path)
      end
    end
  end

  describe "the dependency gate" do
    let(:noop) do
      lambda { |agent, subject, **|
        calls << [agent.name, subject.feature.ordinal.to_s]
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "noop", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
      }
    end

    def frontmatter(**keys) = "---\n#{keys.map { |k, v| "#{k}: #{v}" }.join("\n")}\n---\n#{spec_body}"

    describe "#blockers_first" do
      let!(:built) do
        plans do |t|
          t.plan "001.00", :planned, "free-a", files: { "spec.md" => spec_body }
          t.plan "002.00", :planned, "free-b", files: { "spec.md" => spec_body }
          t.plan "003.00", :planned, "blocker", files: { "spec.md" => spec_body }
          t.plan "004.00", :planned, "waiter", files: { "spec.md" => frontmatter(depends_on: '["003.00"]') }
        end
      end

      let(:dispatcher) { described_class.new(runner: runner_with(noop)) }

      it "puts a plan others wait for ahead of those nobody waits for, keeping order otherwise" do
        ordered = dispatcher.send(:blockers_first, tree.subjects).map { it.feature.ordinal.to_s }

        expect(ordered).to eq(%w[003.00 001.00 002.00 004.00])
      end
    end

    %w[full plan quick].each do |lane|
      context "with the #{lane} lane" do
        let!(:built) do
          plans do |t|
            t.plan "034.00", :blocked, "stuck", files: { "blocked.md" => "## B1 Which?\n" }
            t.plan "050.00",
              :ready_for_planning,
              "waiter",
              files: { "spec.md" => frontmatter(lane:, depends_on: '["034.00"]') }
          end
        end

        it "holds a plan whose dependency is not done" do
          runner = runner_with(noop)
          runner.call

          expect(calls.map(&:last)).not_to include("050.00")
          expect(runner.held).to eq("050.00" => "waiting on 034.00")
        end
      end
    end
  end

  describe ".ticks" do
    it "turns seconds into ticks, so five seconds is ten half-second ticks" do
      expect(described_class.ticks(5)).to eq(10)
    end

    it "never answers fewer than one tick" do
      expect(described_class.ticks(0.1)).to eq(1)
    end
  end
end
