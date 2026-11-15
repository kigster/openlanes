# frozen_string_literal: true

# The arbitrator's side call for time, with only its answer canned.
RSpec.describe OpenLanes::Engine::Arbitration::Overtime, :tree do
  subject(:overtime) { described_class.new(agents:, ask: ->(agent, _plan, brief) { asked << [agent.name, brief]; answers.shift }, retries:) }

  let(:agents) { OpenLanes::Agents::Registry.new }
  let(:retries) { OpenLanes::Engine::Arbitration::Retries.new(clock: -> { now[:t] }) }
  let(:now) { { t: Time.utc(2026, 11, 15, 9) } }
  let(:asked) { [] }
  let(:answers) { [] }
  let(:plan) { OpenLanes::Plans::Tree.new(dir: plans_root).find("001.00") }

  before do
    plans { |t| t.plan "001.00", :building, "work", files: { "spec.md" => spec_body, "plan.md" => "## U" } }
    allow(OpenLanes::UI).to receive(:log)
  end

  def verdict = overtime.verdict(plan, 3) { "Trigger: extension" }

  def answered
    verdict
    overtime.join
    verdict
  end

  it "asks the arbitrator off the loop's thread, and has nothing until it answers" do
    gate = Queue.new
    slow = described_class.new(agents:, ask: ->(*) { gate.pop }, retries:)
    first = slow.verdict(plan, 3) { "brief" }
    gate << "```extension\ndecision: grant\nminutes: 10\nreason: ok\n```\n"
    slow.join
    expect([first, slow.verdict(plan, 3) { "brief" }.seconds]).to eq([nil, 600])
  end

  it "hands the ruling back once, to the arbitrator it asked with the brief" do
    answers << "```extension\ndecision: decline\nreason: looping\n```\n"
    ruling = answered
    expect([ruling.granted?, ruling.reason, asked]).to eq([false, "looping", [["arbitrator", "Trigger: extension"]]])
  end

  it "does not build the brief while a question is under way or backing off" do
    answers << "nothing readable"
    answered
    expect { |brief| overtime.verdict(plan, 3, &brief) }.not_to yield_control
  end

  it "counts an unreadable answer, and a run that failed, and gives up after three" do
    answers.push("no block", "```extension\ndecision: maybe\n```\n")
    failing = described_class.new(agents:, ask: ->(*) { raise OpenLanes::Error, "the arbitrator's run failed" }, retries:)
    seen = [answered]
    now[:t] += 60
    seen << answered
    now[:t] += 120
    failing.verdict(plan, 3) { "brief" }
    failing.join
    seen << failing.verdict(plan, 3) { "brief" }
    expect(seen + [verdict]).to eq([nil, nil, :given_up, :given_up])
  end

  it "gives up at once on a roster without an arbitrator" do
    expect(described_class.new(agents: agents.without("arbitrator"), ask: ->(*) {}, retries:).verdict(plan, 3) { "brief" }).to eq(:given_up)
  end
end
