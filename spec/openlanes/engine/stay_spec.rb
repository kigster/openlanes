# frozen_string_literal: true

require_relative "../live/live_context"

# `openlanes start`, and `run` with its control room: the dispatcher idles
# past every fixed point instead of ending there, and only a quit ends it. The case that asked for it: `openlanes create a web-based
# minesweeper game`, planner asks a question, and the run ended
# with the question on a page that died with it.
RSpec.describe "A staying run", :tree do
  include_context "with a live run"

  let(:stamp) { "2026-10-13 09:00:00 AM PDT" }
  let(:calls) { [] }
  let(:rescan) { 1000 }
  let(:session) { OpenLanes::Live::Session.new(store:, root: File.dirname(plans_root), tree:, agents:, node:, repo: keys.repo) }
  let(:claims) { session.claims }
  let(:runner) do
    OpenLanes::Engine::Runner.new(tree:, executor:, agents:, isolation: :shared, claims:, sleeper: ->(_) {})
  end
  let(:dispatcher) do
    OpenLanes::Engine::Dispatcher.new(runner:, sleeper:, on_board: session.on_board, stay: true, rescan:)
  end

  # Called between ticks, as the real one sleeps a second: here it is the
  # person at the page, and the stopwatch. It never waits.
  let(:script) { ->(_) {} }
  let(:ticks) { [] }
  let(:sleeper) do
    lambda { |seconds|
      ticks << seconds
      script.call(ticks.size)
      OpenLanes::Execution::Control.quit! if ticks.size > 20_000
      Thread.pass
    }
  end

  # Every agent at once: signs Started, does what the example says, signs
  # what that returns.
  let(:behaviour) { ->(_agent, _subject, _round) {} }
  let(:executor) do
    lambda { |agent, subject, round: 1, **|
      calls << agent.name
      file = File.join(subject.feature.path, agent.ledger.first)
      OpenLanes::Plans::Ledger.append(file, "> [#{stamp}] [ agent: #{agent.name}   status: Started, round #{round} ]")
      outcome = behaviour.call(agent, subject, round)
      OpenLanes::Plans::Ledger.append(file, "> [#{stamp}] [ agent: #{agent.name}   status: #{outcome}, round #{round} ]") if outcome
      OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 1, down: 1, subagents: 0, delegated: 0, seconds: 0.1)
    }
  end

  def snapshot = OpenLanes::Live.board(store:, keys: session.keys)[:me]

  def questions = snapshot.fetch("plans").flat_map { it["questions"] || [] }

  def answer(id, question, text)
    OpenLanes::Live.enqueue(store:,
      keys:  session.keys,
      input: { id:, kind: "answer", plan: "020.00", agent: nil, payload: { question:, text: } })
  end

  def status_of(ordinal) = tree.reload.find(OpenLanes::Plans::Ordinal.parse(ordinal)).status.key

  def run_until_stopped
    session.attach(dispatcher)
    dispatcher.run
  ensure
    session.close
  end

  before { allow(OpenLanes::UI).to receive(:log) }

  after { OpenLanes::Execution::Control.reset! }

  describe "planner blocks on a question, the answer comes from the page" do
    let(:agents) { OpenLanes::Agents::Registry.new.only("planner", "unblocker") }
    let(:seen) { {} }
    # depends_on is answered, as planner leaves it once he has planned.
    let(:linked_spec) { "---\ndepends_on: [none]\n---\n#{spec_body}" }

    # Round one asks how big the board is; once unblocker has drained
    # the answer, planner plans.
    let(:behaviour) do
      lambda { |agent, subject, _round|
        path = subject.feature.path
        case agent.name
        when "unblocker"
          File.delete(File.join(path, "blocked.md"))
          nil
        when "planner"
          if calls.count("planner") == 1
            File.write(File.join(path, "blocked.md"), "## B1 Board size\n\nHow many cells a side?\n")
            "Blocked"
          else
            File.write(File.join(path, "plan.md"), "# Plan\n\n## Unit 1\n")
            File.write(File.join(path, "plan-frontend.md"), "# Front end\n\n## F1\n")
            "Completed"
          end
        end
      }
    end

    # The page: once the question shows in Needs You, with nothing running,
    # it is answered; once planner has run again and the run idles, the
    # person stops it.
    let(:script) do
      lambda { |_|
        if !seen[:question] && dispatcher.running.empty? && (asked = questions.first)
          seen[:question] = asked
          seen[:idle] = snapshot.dig("run", "status")
          answer("01ANSWER", "B1", "Nine.")
        end
        if calls.count("planner") == 2 && dispatcher.running.empty? && dispatcher.board.status == :idle
          OpenLanes::Execution::Control.quit!
        end
      }
    end

    before do
      plans { |t| t.plan "020.00", :ready_for_planning, "minesweeper", files: { "spec.md" => linked_spec, "plan.md" => "" } }
      run_until_stopped
    end

    it "keeps running past the block, shows the question, drains the answer, and starts planner again" do
      aggregate_failures do
        expect(seen[:question]).to include("id" => "020.00/B1", "body" => "How many cells a side?")
        expect(seen[:idle]).to eq("idle")
        expect(calls).to eq(%w[planner unblocker planner])
        expect(status_of("020.00")).to eq(:planned)
      end
    end
  end

  describe "a project with no plans yet" do
    let(:agents) { OpenLanes::Agents::Registry.new.only("researcher") }
    let(:behaviour) do
      lambda { |_agent, subject, _round|
        File.write(File.join(subject.feature.path, "spec.md"), "#{spec_body}\n## Research\n\nFound.\n")
        "Completed"
      }
    end

    # The first plan arrives after a few idle ticks, the way `openlanes create`
    # in another terminal makes one: no command, so the rescan finds it.
    let(:rescan) { 3 }
    let(:script) do
      lambda { |tick|
        plans { |t| t.plan "001.00", :new, "minesweeper", files: { "spec.md" => spec_body } } if tick == 5
        OpenLanes::Execution::Control.quit! if calls.any? && dispatcher.running.empty? && dispatcher.board.status == :idle
      }
    end

    before { run_until_stopped }

    it "waits for the first plan instead of calling an empty tree complete, and picks it up on a rescan" do
      expect([calls, status_of("001.00")]).to eq([%w[researcher], :researched])
    end

    it "says what it is waiting for" do
      expect(OpenLanes::UI).to have_received(:log).with("idle: no plans yet; create one from the page or with openlanes create")
    end
  end

  describe "a plan created from the page" do
    let(:agents) { OpenLanes::Agents::Registry.new.only("researcher") }

    let(:script) do
      lambda { |tick|
        if tick == 2
          OpenLanes::Live.enqueue(store:,
            keys:  session.keys,
            input: { id: "01IDEA", kind: "create_plans", plan: nil, agent: nil, payload: { idea: "web based minesweeper game" } })
        end
        OpenLanes::Execution::Control.quit! if calls.any? && dispatcher.running.empty?
      }
    end

    before { run_until_stopped }

    it "joins the run at once, without waiting for the rescan" do
      expect([calls, ticks.size < rescan]).to eq([%w[researcher], true])
    end
  end

  describe "when every plan is finished" do
    let(:agents) { OpenLanes::Agents::Registry.new.only("researcher") }
    let(:script) { ->(tick) { OpenLanes::Execution::Control.quit! if tick == 30 } }

    before do
      plans do |t|
        t.plan "001.00", :deployed, "shipped", files: { "spec.md" => spec_body, "deployed.md" => "v1\n" }
        t.plan "002.00", :deployed, "also-shipped", files: { "spec.md" => spec_body, "deployed.md" => "v2\n" }
      end
      run_until_stopped
    end

    it "stays up for the next plan from the page, until a person stops it" do
      expect(ticks.size).to eq(30)
    end

    it "says so" do
      expect(OpenLanes::UI).to have_received(:log).with("idle: every plan is finished; create the next one from the page")
    end
  end

  describe "a plan still waiting on review" do
    let(:agents) { OpenLanes::Agents::Registry.new.only("researcher") }
    let(:asked) { [] }
    let(:script) do
      lambda { |tick|
        asked.replace(questions.map { it["id"] }) if tick == 29
        OpenLanes::Execution::Control.quit! if tick == 30
      }
    end

    before do
      plans do |t|
        t.plan "001.00", :deployed, "shipped", files: { "spec.md" => spec_body, "deployed.md" => "v1\n" }
        t.plan "002.00", :blocked, "asked", files: { "spec.md" => spec_body, "blocked.md" => "## B1 Which?\n\nThis or that?\n" }
      end
      run_until_stopped
    end

    it "is not finished: only a person stops it" do
      expect(ticks.size).to eq(30)
    end

    it "puts the blocked plan's question on the page though no agent touched it this run" do
      expect(asked).to eq(%w[002.00/B1])
    end

    it "says whose answers it is waiting for" do
      expect(OpenLanes::UI).to have_received(:log).with("idle: waiting for answers on 002.00")
    end
  end

  describe "resting between rescans" do
    let(:agents) { OpenLanes::Agents::Registry.new.only("researcher") }
    let(:rescan) { 5 }
    let(:scans) { [] }

    before do
      plans { |t| t.plan "001.00", :blocked, "asked", files: { "spec.md" => spec_body, "blocked.md" => "## B1 Which?\n\nThis?\n" } }
      allow(OpenLanes::Lifecycle::Resync::Dirs).to receive(:new).and_wrap_original do |original, **keywords|
        scans << ticks.size
        original.call(**keywords)
      end
      dispatcher.tick
      11.times do |i|
        ticks << i
        dispatcher.tick
      end
      dispatcher.wake!
      dispatcher.tick
    end

    it "scans once every rescan interval while idle, and at once when woken" do
      expect(scans).to eq([0, 5, 10, 11])
    end
  end

  describe "Stop All Local from the page" do
    let(:agents) { OpenLanes::Agents::Registry.new }
    let(:executor) { HeldExecutor.new(traces) }
    let(:dispatcher) { OpenLanes::Engine::Dispatcher.new(runner:, sleeper: ->(_) {}, stay: true, rescan:) }

    before do
      building("001.00", "tax-rule-dsl")
      start_agents
      session.attach(dispatcher)
      OpenLanes::Live.enqueue(store:, keys: session.keys, input: { id: "01STOP", kind: "stop_all", plan: nil, agent: nil, payload: {} })
      dispatcher.tick
    end

    after { session.close }

    it "stops the agents, and then the run" do
      aggregate_failures do
        expect(dispatcher.running.map { File.read(it.handle.control).strip }.uniq).to eq(%w[STOP])
        expect(OpenLanes::Execution::Control.quit?).to be(true)
        expect(JSON.parse(store.hget(session.keys.done, "01STOP"))["reason"])
          .to include("the engine and the control room shut down once they have gone")
      end
    end
  end
end
