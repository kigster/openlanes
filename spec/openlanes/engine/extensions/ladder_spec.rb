# frozen_string_literal: true

require "json_schemer"

# The ladder over a real `.plans` tree, a real handle and a real clock, with
# the real side call to the arbitrator. Only the arbitrator's answer is
# canned, where the executor would run claude.
RSpec.describe OpenLanes::Engine::Extensions::Ladder, :tree do
  subject(:ladder) { described_class.new(extensions:, overtime: -> { overtime }) }

  let(:extensions) { OpenLanes::Engine::Extensions.new(stay: true, now: -> { now }) }
  let(:retries) { OpenLanes::Engine::Arbitration::Retries.new(clock: -> { now }) }
  let(:overtime) { OpenLanes::Engine::Arbitration::Overtime.new(agents: OpenLanes::Agents::Registry.new, ask: ->(*) { answers.shift }, retries:) }
  let(:answers) { [] }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:plan_subject) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")) }
  let(:plan) { OpenLanes::Plans::PlanState.for(plan_subject.feature.path) }
  let(:control) { File.join(Dir.mktmpdir, "control") }
  let(:handle) { handle_with(300) }
  let(:agent) { OpenLanes::Agents::Registry.new(overrides: OpenLanes::Agents::Overrides.new).find("backend-coder") }
  let(:job) do
    task = OpenLanes::Engine::Runner::Task.new(agent:, subject: plan_subject, root: plans_root, checkout: plans_root, round: 1)
    OpenLanes::Engine::Dispatcher::Job.new(key: "001.00/backend-coder", task:, state: :building, handle:, started_at: OpenLanes::UI.monotonic)
  end

  before do
    plans { |t| t.plan "001.00", :building, "tax-rule-dsl", files: { "spec.md" => spec_body, "plan.md" => "# P" } }
    allow(OpenLanes::UI).to receive(:log)
  end

  # The wall clock the deadlines read, and the one the agent's clock runs on.
  attr_writer :now

  def now = @now ||= Time.utc(2026, 11, 15, 9)
  def ticks = @ticks ||= { t: 0.0 }
  def watch = ladder.watch(job, plan_subject)
  def said = File.read(control).strip
  def requests = plan.extensions
  def estimate(seconds, why: "two units left") = plan.estimate_extension!(agent: "backend-coder", seconds:, why:, at: now)

  # A handle on a clock with +left+ seconds on it.
  def handle_with(left)
    File.write(control, "")
    clock = OpenLanes::Execution::Clock.new(seconds: left, control:, on_expire: -> {}, now: -> { ticks[:t] })
    OpenLanes::Execution::Executor::Handle.new.tap { it.clock = clock }
  end

  # The agent's clock run down to +left+ seconds.
  def run_down_to(left) = ticks[:t] += handle.remaining - left

  # The first step taken and its time used up: the agent is asked.
  def asked
    watch
    run_down_to(300)
    watch
  end

  # Past the ask, with an estimate too large to grant unasked.
  def at_the_arbitrator
    asked
    estimate(2400)
    watch
  end

  # One answer from the arbitrator, read on the tick after it came.
  def ruled
    watch
    overtime.join
    watch
  end

  it "is due only when the clock is low or a decision is out" do
    aggregate_failures do
      expect(ladder.due?(job)).to be(true)
      expect(described_class.new(extensions:).due?(job.dup.tap { it.handle = handle_with(301) })).to be(false)
    end
  end

  describe "step 1, with the clock low" do
    it "adds the whole cap on its own, to the clock that is running" do
      granted = watch
      aggregate_failures do
        expect(granted).to include("by" => "auto", "grant" => "live", "seconds" => 900, "limit" => "time", "round" => 1)
        expect(handle.remaining).to eq(1200)
        expect(said).to eq("WARN: 20 minutes left, time was extended")
        expect(requests.size).to eq(1)
        expect(OpenLanes::Engine::Extensions.questions(plan_subject, plan)).to eq([])
      end
    end

    it "adds no more than the cap in one round" do
      asked
      expect(requests.select { it["by"] == "auto" }.sum { it["seconds"] }).to eq(900)
    end

    it "reads the cap from the agent, where `.openlanes/config.yml` `agents:` put it" do
      job.task = job.task.with(agent: agent.with(extension_cap: 300))
      expect(watch).to include("seconds" => 300)
    end

    it "starts again on the next round" do
      asked
      extensions.close!(plan_subject.feature.path, "backend-coder", :building)
      job.task = job.task.with(round: 2)
      expect(watch).to include("by" => "auto", "round" => 2)
    end

    it "asks a person at once, and grants nothing, on a run told never to grant on its own" do
      described_class.new(extensions: OpenLanes::Engine::Extensions.new(stay: true, auto: false, now: -> { now })).watch(job, plan_subject)
      aggregate_failures do
        expect(requests).to contain_exactly(include("limit" => "time").and(satisfy { !it.key?("settled_at") && !it.key?("stage") }))
        expect(handle.remaining).to eq(300)
      end
    end

    it "gives the time with a round when the clock had already stopped, once" do
      run_down_to(0)
      handle.clock.tick
      2.times { watch }
      aggregate_failures do
        expect(requests.select { it["by"] == "auto" }).to contain_exactly(include("grant" => "round", "seconds" => 900))
        expect(extensions.rounds(plan_subject.feature.path, "backend-coder", :building)).to eq(1)
      end
    end
  end

  describe "step 2, with the added time low too" do
    before { asked }

    it "asks the agent, in its control file, and shows a person nothing" do
      aggregate_failures do
        expect(requests.last).to include("stage" => "estimate", "limit" => "time").and(satisfy { !it.key?("settled_at") })
        expect(said).to start_with("ESTIMATE: about 5 minutes left.").and(include("openlanes state estimate"))
        expect(OpenLanes::Engine::Extensions.questions(plan_subject, plan)).to eq([])
      end
    end

    it "holds the clock above WRAP_UP while it waits, and never stops the agent" do
      run_down_to(30)
      watch
      aggregate_failures do
        expect(handle.remaining).to eq(described_class::HOLD_AT)
        expect(handle.phase).not_to eq(:stopped)
        expect(said).to start_with("ESTIMATE:")
      end
    end

    it "raises a held clock in steps, not on every tick" do
      run_down_to(described_class::HOLD_AT - described_class::HOLD_STEP + 1)
      watch
      expect(handle.remaining).to eq(described_class::HOLD_AT - described_class::HOLD_STEP + 1)
    end

    it "keeps reading a request whose held clock is no longer low" do
      handle.extend!(600)
      expect(ladder.due?(job)).to be(true)
    end

    it "asks once: the same request, however many ticks pass" do
      3.times { watch }
      expect(requests.count { it.key?("stage") }).to eq(1)
    end
  end

  describe "step 3, an estimate within the cap" do
    before { asked }

    it "is granted as asked, by the agent's own estimate" do
      estimate(600)
      granted = watch
      aggregate_failures do
        expect(granted).to include("by" => "estimate", "grant" => "live", "seconds" => 600, "estimate" => 600, "why" => "two units left")
        expect(handle.remaining).to eq(900)
        expect(said).to eq("WARN: 15 minutes left, time was extended")
        expect(ladder.due?(job)).to be(false)
      end
    end

    it "is granted at the cap itself" do
      estimate(900)
      expect(watch).to include("seconds" => 900)
    end

    it "leaves the next shortfall of the round to a person" do
      estimate(600)
      watch
      run_down_to(300)
      watch
      aggregate_failures do
        expect(requests.last).to include("limit" => "time").and(satisfy { !it.key?("settled_at") && !it.key?("stage") })
        expect(OpenLanes::Engine::Extensions.questions(plan_subject, plan).map { it[:kind] }).to eq(["extension"])
      end
    end
  end

  describe "step 4, an estimate above the cap" do
    before { at_the_arbitrator }

    it "goes to the arbitrator, with the agent kept working" do
      aggregate_failures do
        expect(requests.last).to include("stage" => "arbitration", "estimate" => 2400, "staged_at" => now.iso8601)
        expect(OpenLanes::Engine::Extensions.questions(plan_subject, plan)).to eq([])
        expect(handle.remaining).to be >= described_class::HOLD_AT
      end
    end

    it "grants what the arbitrator grants" do
      answers << "Fine.\n\n```extension\ndecision: grant\nminutes: 30\nreason: Two units remain.\n```\n"
      granted = ruled
      aggregate_failures do
        expect(granted).to include("by" => "arbitrator", "grant" => "live", "seconds" => 1800, "reason" => "Two units remain.")
        expect(handle.remaining).to eq(300 + 1800)
      end
    end

    it "cuts a grant to the agent's ceiling" do
      answers << "```extension\ndecision: grant\nminutes: 600\nreason: Plenty.\n```\n"
      expect(ruled).to include("seconds" => 3600)
    end

    it "tells the arbitrator who asks, for how much, why, and the most it may grant" do
      briefs = []
      allow(overtime).to(receive(:verdict).and_wrap_original { |original, *args, &brief| original.call(*args) { briefs << brief.call; briefs.last } })
      answers << "```extension\ndecision: decline\nreason: no\n```\n"
      ruled
      expect(briefs.first).to include("Trigger: extension",
        "Raised by: backend-coder, round 1 on building",
        "Asks for: 40 more minutes",
        "Says: two units left",
        "Most you may grant: 60 minutes",
        "15 of them added by the engine")
    end

    it "hands a decline to a person, with the reason" do
      answers << "```extension\ndecision: decline\nreason: It is looping.\n```\n"
      ruled
      aggregate_failures do
        expect(requests.last).to include("stage" => "person", "note" => "the arbitrator declined: It is looping.")
        expect(OpenLanes::Engine::Extensions.questions(plan_subject, plan).first).to include(kind: "extension", number: requests.last["number"])
        expect(said).to start_with("WARN: ")
      end
    end

    it "asks again after an unreadable answer only once its back-off has passed" do
      answers << "no block" << "```extension\ndecision: grant\nminutes: 20\nreason: ok\n```\n"
      ruled
      watch
      expect(answers.size).to eq(1)

      self.now = now + OpenLanes::Engine::Arbitration::BACKOFF
      expect(ruled).to include("by" => "arbitrator", "seconds" => 1200)
    end

    it "hands the request to a person once the arbitrator is given up on" do
      answers.push("no block", "still none", "nor now")
      3.times do
        ruled
        self.now = now + 150
      end
      watch
      expect(requests.last).to include("stage" => "person", "note" => "the arbitrator's answer could not be read")
    end

    it "hands the request to a person when no ruling comes in time, and stops holding the clock" do
      allow(overtime).to receive(:verdict).and_return(nil)
      self.now = now + described_class::RULING_WITHIN
      watch
      run_down_to(0)
      watch
      aggregate_failures do
        expect(requests.last).to include("stage" => "person", "note" => "the arbitrator did not rule in time")
        expect(handle.remaining).to eq(0)
      end
    end
  end

  describe "step 4 on a run with no arbitrator" do
    let(:overtime) { nil }

    it "hands a large estimate straight to a person" do
      at_the_arbitrator
      watch
      expect(requests.last).to include("stage" => "person", "note" => "this run has no arbitrator")
    end
  end

  describe "step 5, when the agent never answers" do
    before { asked }

    it "waits out the deadline, then raises the person's card as it always was" do
      self.now = now + described_class::REPLY_WITHIN - 1
      watch
      expect(OpenLanes::Engine::Extensions.questions(plan_subject, plan)).to eq([])

      self.now = now + 1
      watch
      card = OpenLanes::Engine::Extensions.questions(plan_subject, plan).first
      aggregate_failures do
        expect(card).to include(kind: "extension", heading: "backend-coder is running out of time", agent: "backend-coder", held: false)
        expect(card[:options].map { it[:letter] }).to eq(%w[a b c])
        expect(requests.last).to include("note" => "no estimate from backend-coder")
      end
    end

    it "lets the clock run out once the card is a person's" do
      self.now = now + described_class::REPLY_WITHIN
      watch
      run_down_to(0)
      watch
      handle.clock.tick
      expect([handle.remaining, handle.phase]).to eq([0, :stopped])
    end

    it "takes a person's answer on the escalated card, onto the running clock" do
      self.now = now + described_class::REPLY_WITHIN
      watch
      settled = extensions.answer!(plan_subject.feature.path, requests.last["number"], "c", by: "pat", live: handle)
      expect([settled["by"], settled["grant"], handle.remaining]).to eq(["pat", "live", 300 + 1200])
    end

    it "takes no estimate that arrives after it stopped waiting" do
      self.now = now + described_class::REPLY_WITHIN
      watch
      expect(estimate(600)).to be_nil
    end
  end

  describe "across an engine restart" do
    # A new engine: nothing in memory, the agent's clock rearmed where it stood.
    def restarted = described_class.new(extensions:, overtime: -> { overtime })

    it "does not grant the automatic time twice" do
      watch
      run_down_to(300)
      restarted.watch(job, plan_subject)
      expect(requests.select { it["by"] == "auto" }.size).to eq(1)
    end

    it "takes up a request the agent was asked about, without asking again" do
      asked
      estimate(600)
      again = restarted
      expect(again.watch(job, plan_subject)).to include("by" => "estimate", "seconds" => 600)
      expect(requests.count { it.key?("stage") }).to eq(1)
    end

    it "does not grant an estimate twice" do
      asked
      estimate(600)
      watch
      before = handle.remaining
      restarted.watch(job, plan_subject)
      expect(handle.remaining).to eq(before)
    end

    it "asks the arbitrator again for a request that was with it, inside the same deadline" do
      at_the_arbitrator
      again = restarted
      answers << "```extension\ndecision: grant\nminutes: 20\nreason: ok\n```\n"
      again.watch(job, plan_subject)
      overtime.join
      expect(again.watch(job, plan_subject)).to include("by" => "arbitrator", "seconds" => 1200)
    end
  end

  it "forgets a round that ended" do
    asked
    ladder.forget(job)
    handle.extend!(600)
    expect(ladder.due?(job)).to be(false)
  end

  it "writes requests the plan-state schema accepts, at every stage" do
    at_the_arbitrator
    answers << "```extension\ndecision: decline\nreason: no\n```\n"
    ruled
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path("../../../../schemas/plan-state.schema.json", __dir__))))
    expect(schema.validate(JSON.parse(File.read(plan.path))).to_a).to eq([])
  end
end
