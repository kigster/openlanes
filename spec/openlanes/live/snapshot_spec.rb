# frozen_string_literal: true

require "json"
require_relative "live_context"

RSpec.describe OpenLanes::Live::Snapshot, :tree do
  subject(:snapshot) do
    described_class.new(board:,
      tree:,
      agents:,
      node:,
      repo: keys.repo,
      project: "openlanes",
      seq: 42,
      description: "A software factory",
      at:,
      started_at: at - 60,
      claims:,
      run_state:,
      meter:,
      log:).to_h
  end

  include_context "with a live run"

  let(:at) { Time.utc(2026, 10, 13, 9) }
  let(:meter) { OpenLanes::Live::Meter.new }
  let(:log) { [{ at: "2026-10-13T09:00:00Z", source: "engine", level: "info", text: "started", plan: "001.00" }] }
  let(:fixture) { JSON.parse(File.read(File.expand_path("../../../web/src/api/fixtures/snapshot.json", __dir__))) }
  let(:rows) { [] }
  let(:board) do
    OpenLanes::Engine::Board.new(started_at: 0,
      status: :running,
      plans: rows.map(&:ordinal).uniq,
      up: 2_000_000,
      down: 200_000,
      rows:,
      root: File.dirname(plans_root),
      running: rows.count(&:running?),
      live_up: 0,
      live_down: 0)
  end

  def row(ordinal, agent, model: "sonnet", state: :running, up: 1_000_000, down: 100_000, **)
    OpenLanes::Engine::Board::Row.new(key: "#{ordinal}/#{agent}",
      at: at,
      ordinal:,
      file: "plan.md",
      agent:,
      role: agent.split("-").last,
      round: 1,
      rounds: 2,
      model:,
      remaining: 971,
      phase: :calm,
      up:,
      down:,
      message: "working",
      state:,
      elapsed: 229,
      history: ["working"],
**)
  end

  # Every key at every level, arrays folded into the union of their
  # elements' keys, so the comparison is about shape and not about values.
  def shape(value)
    case value
    when Hash then value.to_h { |k, v| [k.to_s, shape(v)] }
    when Array then value.map { shape(it) }.reduce { |a, b| merge(a, b) }
    end
  end

  def merge(left, right)
    return left || right unless left.is_a?(Hash) && right.is_a?(Hash)

    left.merge(right) { |_, a, b| merge(a, b) }
  end

  describe "against the page's fixture" do
    before do
      blocked("001.00",
        "clean-boundaries",
        "# Blocked\n\n## B1 Redis key layout\n\nShould keys carry the path?\n\n" \
        "## B2 Rebase\nanswers: yes, no\n\nShould I rebase onto main?\n")
      state = OpenLanes::Plans::PlanState.for(path_of("001.00"))
      state.stage!(agent: "luke-backend", round: 1, status: "Blocked", from: "building", effort: "high")
      state.sign!(agent: "luke-backend", round: 1, status: "Blocked", note: "technical", at: at)
      state.record_last_known("rey-frontend",
        OpenLanes::Plans::LastKnownState.new(source: "harness",
          round: 1,
          status: "Interrupted",
          next_step: "draw the panel",
          note: "harness died"))
      plans do |t|
        t.plan "005.00",
          :in_review,
          "review-state-labels",
          files: { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## U1\n" },
          prs:   [t.open(44, "Review state labels")]
        t.plan "013.00", :new, "plain-numbers", files: { "spec.md" => spec_body }
        t.plan "012.00", :product_blocked, "linear-sync", files: { "spec.md" => spec_body, "blocked.md" => "## B1 Which?\n" }
        t.plan "014.00", :approved, "shipped", files: { "spec.md" => spec_body }
        t.plan "015.00", :new, "theirs", files: { "spec.md" => spec_body }
        t.plan "016.00", :bomb, "stack-ports", files: { "spec.md" => spec_body, "blocked.md" => "## B1 Which port range?\n" }
      end
      store.set(keys.claim("015.00"), "ffffffffffffffffffffffff:000000000000")
      claims.claim("001.00")
      meter.record(rows, now: at - 30)
    end

    let(:rows) do
      [row("001.00", "luke-backend", model: "opus", up: 374_000, down: 26_400),
       row("001.00", "rey-frontend"),
       row("005.00", "hansolo-reviewer")]
    end

    let(:blocked_plan) { snapshot[:plans].find { it[:ordinal] == "001.00" } }
    let(:by_ordinal) { snapshot[:plans].to_h { [it[:ordinal], it] } }

    it "reports a plan's lock, and null for a plan without one" do
      dir = Dir.glob(File.join(plans_root, "001.00*")).first
      OpenLanes::Plans::Lock.write(dir, now: Time.utc(2026, 10, 13, 9))

      expect(by_ordinal["001.00"][:locked]).to eq(pid: Process.pid, host: Socket.gethostname, started_at: "2026-10-13T09:00:00Z")
      expect(by_ordinal.except("001.00").values.map { it[:locked] }.uniq).to eq([nil])
    end

    it "has the fixture's keys at every level" do
      expect(shape(JSON.parse(JSON.generate(snapshot)))).to eq(shape(fixture))
    end

    it "counts unacked mail and carries each agent's resume record, and nothing for a plan without them" do
      OpenLanes::Plans.mailbox(path_of("001.00")).append(from: "luke-backend", to: "rey-frontend", body: "B1 landed")

      aggregate_failures do
        expect(blocked_plan[:unacked]).to eq(1)
        expect(blocked_plan[:last_known]).to match([{ agent: "rey-frontend", source: "harness", at: anything, round: 1,
          status: "Interrupted", next_step: "draw the panel", note: "harness died" }])
        expect(by_ordinal["005.00"].values_at(:unacked, :last_known)).to eq([0, []])
      end
    end

    it "derives the stations from the spine and the agents' handles" do
      expect(snapshot[:stations].map { [it[:key], it[:label]] }).to eq(fixture["stations"].map { [it["key"], it["label"]] })
    end

    it "lists the agents at each station from their definitions" do
      expect(snapshot[:stations].to_h { [it[:key], it[:agents]] }).to include(
        "new"                => %w[leah-researcher],
        "ready_for_planning" => %w[palpatine-planner],
        "pr"                 => [],
        "in_review"          => %w[chewie-verifier hansolo-reviewer]
      )
    end

    it "shows a plan stopped for a question at the station it stopped in, its agents stuck" do
      aggregate_failures do
        expect(blocked_plan[:station]).to eq("building")
        expect(blocked_plan[:cars].map { it[:state] }).to eq(%w[stuck stuck])
        expect(blocked_plan[:cars].first).to include(model: "claude-opus-5-5", effort: "high", phase: "calm", held: false)
        expect(blocked_plan[:claimed_by]).to eq(node.id)
      end
    end

    it "offers Yes and No only for the question the agent marked, without the mark" do
      aggregate_failures do
        expect(blocked_plan[:questions].map { it[:options]&.map { |o| o[:answer] } }).to eq([nil, %w[yes no]])
        expect(blocked_plan[:questions].map { it[:heading] }).to eq(["B1 Redis key layout", "B2 Rebase"])
        expect(blocked_plan[:questions].map { it[:body] }).to eq(["Should keys carry the path?", "Should I rebase onto main?"])
        expect(blocked_plan[:questions].first).to include(id: "001.00/B1",
          agent: "luke-backend",
          owner: "technical",
          asked_at: "2026-10-13T09:00:00Z")
      end
    end

    it "prices what each plan spent at its models' rates" do
      aggregate_failures do
        expect(by_ordinal["005.00"].slice(:up, :down, :cost)).to eq(up: 1_000_000, down: 100_000, cost: 3.0)
        expect(by_ordinal["001.00"][:cost]).to eq(((374_000 * 4) + (26_400 * 20) + (1_000_000 * 2) + (100_000 * 10)) / 1e6)
        expect(snapshot[:run][:cost]).to eq((by_ordinal["005.00"][:cost] + by_ordinal["001.00"][:cost]).round(4))
        expect(by_ordinal["005.00"][:elapsed]).to eq(30)
      end
    end

    it "carries an open pull request as open" do
      expect(snapshot[:plans].find { it[:ordinal] == "005.00" }[:pr])
        .to eq(number: 44, url: "https://github.com/example/repo/pull/44", state: "open", ci: nil, merged_at: nil)
    end

    it "offers as backlog what is neither finished, nor ours, nor another machine's" do
      expect(snapshot[:backlog].map { it[:ordinal] }).to eq(%w[012.00 013.00 016.00])
    end

    it "describes the run, the node and the models" do
      aggregate_failures do
        expect(snapshot[:run]).to include(status: "running", started_at: "2026-10-13T08:59:00Z", agents_working: 3)
        expect(snapshot[:node]).to include(user: "dana", me: true, heartbeat_at: "2026-10-13T09:00:00Z")
        expect(snapshot[:models].map { it[:id] }).to eq(%w[claude-opus-5-5 claude-opus-5 claude-sonnet-5-5 claude-sonnet-5 claude-haiku-5-5])
        expect(snapshot[:autocompact]).to eq(0.4)
      end
    end

    it "carries the run's concurrency limit as jobs" do
      expect(snapshot[:run][:jobs]).to eq(1)
    end

    context "when the copilot's /concurrency has set the limit" do
      let(:board) { super().with(jobs: 3) }

      it "carries the new limit, which the page's header reads" do
        expect(snapshot[:run]).to include(jobs: 3, agents_working: 3)
      end
    end

    context "when a person has held a question and an agent" do
      before do
        run_state.hold_question("001.00/B1")
        run_state.hold_car("001.00/rey-frontend")
      end

      it "says so" do
        expect([blocked_plan[:questions].map { it[:held] }, blocked_plan[:cars].map { it[:held] }]).to eq([[true, false], [false, true]])
      end
    end
  end

  describe "a question that offers lettered options (D3)" do
    subject(:question) do
      described_class.new(board:, tree:, agents:, node:, repo: keys.repo, project: "openlanes", seq: 1, at:, claims:, judge:)
                     .to_h[:plans].find { it[:ordinal] == "001.00" }[:questions].first
    end

    let(:judge) { nil }

    before do
      blocked("001.00",
        "clean-boundaries",
        "# Blocked\n\n## B1 Layout\n\nWhich layout?\n\na) Path (Recommended)\nb) Remote URL\nc) Type something instead\n")
      claims.claim("001.00")
    end

    it "shows the context as the body and the options as buttons, the free-text one left to the box" do
      aggregate_failures do
        expect(question[:body]).to eq("Which layout?")
        expect(question[:options]).to eq([{ letter: "a", label: "Path", recommended: true, answer: "a) Path" },
                                          { letter: "b", label: "Remote URL", recommended: false, answer: "b) Remote URL" }])
      end
    end

    context "when the judge says it does not ask to choose" do
      let(:judge) { ->(_text) { false } }

      it "offers the text box alone, with the whole question as its body" do
        expect(question).to include(options: nil, body: start_with("Which layout?\n\na) Path"))
      end
    end

    context "when the judge has no verdict" do
      let(:judge) { ->(_text) {} }

      it "keeps the parser's options" do
        expect(question[:options].size).to eq(2)
      end
    end
  end

  describe "bombs" do
    let(:path) do
      path = nil
      plans { |t| path = t.plan "016.00", :bomb, "stack-ports", files: { "spec.md" => spec_body, "blocked.md" => "## B1 Range?\n" } }
      path
    end

    before do
      OpenLanes::Plans::PlanState.for(path).sign!(agent: "luke-backend", round: 1, status: "Blocked", at: at - 86_400)
    end

    it "lists every 💣, on the board or not, with its blocked.md and when it was blocked" do
      expect(snapshot[:bombs]).to eq([{ plan: "016.00", slug: "stack-ports", blocked_md: "## B1 Range?\n",
                                        blocked_since: "2026-10-12T09:00:00Z", resume_until: nil }])
    end

    it "says until when a halt is lifted" do
      OpenLanes::Plans::PlanState.for(path).resume_anyway!(till: at + 3600)
      expect(snapshot[:bombs].first[:resume_until]).to eq("2026-10-13T10:00:00Z")
    end

    it "is empty, never missing, when nothing has bombed" do
      FileUtils.rm_rf(path)
      expect(snapshot[:bombs]).to eq([])
    end
  end

  describe "a quiet run" do
    before { building("001.00", "tax-rule-dsl") }

    it "is idle, with nothing on the board" do
      expect([snapshot[:run][:status], snapshot[:plans]]).to eq(["idle", []])
    end
  end

  describe "a plan whose agent was interrupted" do
    before do
      building("001.00", "tax-rule-dsl")
      OpenLanes::Plans::PlanState.for(path_of("001.00"))
                                 .stage!(agent: "luke-backend",
                                   round: 1,
                                   status: "Interrupted",
                                   note: "harness died",
                                   finished_at: "2026-10-13T08:00:00Z")
      claims.claim("001.00")
    end

    it "carries who, when and why, until the agent runs again" do
      expect(snapshot[:plans].first[:interrupted]).to eq(agent: "luke-backend", at: "2026-10-13T08:00:00Z", note: "harness died")
    end

    context "when the agent is running again" do
      let(:rows) { [row("001.00", "luke-backend")] }

      it "carries nothing" do
        expect(snapshot[:plans].first[:interrupted]).to be_nil
      end
    end
  end

  describe "a car's context and next model" do
    before { building("001.00", "tax-rule-dsl") }

    let(:rows) { [row("001.00", "luke-backend", model: "opus", context: 54_100)] }
    let(:car) { snapshot[:plans].first[:cars].first }

    it "carries the context the stream reported, against the model's window" do
      expect(car.slice(:context, :context_limit)).to eq(context: 54_100, context_limit: 200_000)
    end

    it "has no window for a model the catalogue does not know" do
      rows.replace([row("001.00", "luke-backend", model: "codex:gpt-5-codex")])
      expect(car.slice(:context, :context_limit)).to eq(context: nil, context_limit: nil)
    end

    it "names the model queued for the next round" do
      run_state.choose_model("001.00/luke-backend", "claude-haiku-5-5")
      expect(car[:next_model]).to eq("claude-haiku-5-5")
    end

    it "names none once a round runs on it" do
      run_state.choose_model("001.00/luke-backend", "claude-opus-5-5")
      expect(car[:next_model]).to be_nil
    end

    it "names the sub-agents still running, and none for a row that has none" do
      rows.replace([row("001.00", "luke-backend", running: %w[Explore leah-researcher]), row("001.00", "rey-frontend")])
      expect(snapshot[:plans].first[:cars].map { it[:subagents] }).to eq([%w[Explore leah-researcher], []])
    end
  end

  describe "the Redis URL" do
    it "is the engine's own, with its userinfo redacted" do
      expect(described_class.new(board:,
        tree:,
        agents:,
        node:,
        repo: keys.repo,
        project: "openlanes",
        seq: 1,
        redis_url: "redis://dana:secret@10.0.4.2:6379/0").to_h[:redis_url]).to eq("redis://:***@10.0.4.2:6379/0")
    end

    it "is null when nobody said which" do
      expect(snapshot[:redis_url]).to be_nil
    end
  end

  describe "an unclaimed plan" do
    before { building("001.00", "tax-rule-dsl") }

    let(:rows) { [row("001.00", "luke-backend")] }

    it "is claimed by nobody, not by an empty name" do
      expect(snapshot[:plans].first[:claimed_by]).to be_nil
    end
  end

  describe "pull requests in their other states" do
    before do
      plans do |t|
        files = { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## U1\n" }
        t.plan "001.00", :rejected, "rejected", files:, prs: [t.open(1, "One")]
        t.plan "002.00", :approved, "approved", files:, prs: [t.open(2, "Two")]
        t.plan "003.00", :approved, "merged", files:, prs: [t.merged(3, "Three")]
        t.plan "004.00", :in_review, "closed", files:, prs: [t.pr(4, "Four", "Closed ⚫️")]
      end
      %w[001.00 002.00 003.00 004.00].each { claims.claim(it) }
    end

    it "names each as the page does" do
      expect(snapshot[:plans].map { it[:pr][:state] }).to eq(%w[rejected approved merged closed])
    end
  end

  describe "models the adapter does not price" do
    before do
      building("001.00", "tax-rule-dsl")
      meter.record(rows)
    end

    let(:rows) { [row("001.00", "luke-backend", model: "codex:gpt-5-codex"), row("001.00", "rey-frontend", model: "zz:odd")] }

    it "keeps each model's own name, and costs nothing on the meter" do
      expect([snapshot[:plans].first[:cars].map { it[:model] }, snapshot[:plans].first[:cost]]).to eq([%w[gpt-5-codex odd], 0.0])
    end
  end
end
