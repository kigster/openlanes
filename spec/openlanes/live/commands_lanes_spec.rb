# frozen_string_literal: true

require_relative "live_context"

# The copilot's slash commands as the engine applies them (plan 020.00):
# stop_plan, restart_plan and set_concurrency, each answered on `replies` and,
# because the copilot sent it, in the conversation as turn "<id>.1".
RSpec.describe OpenLanes::Live::Commands, :tree do
  subject(:commands) do
    described_class.new(store:, keys:, node:, run_state:, claims:, clock: -> { Time.utc(2026, 10, 16, 9) })
  end

  include_context "with a live run"

  let(:runner) do
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :worktree,
      jobs: 3,
      dry_run: true,
      claims:,
      sleeper: ->(_) {})
  end

  def send_command(kind, id:, plan: nil, **payload)
    OpenLanes::Live.enqueue(store:, keys:, input: { id:, kind:, plan:, agent: nil, payload: payload.merge(source: "copilot") })
  end

  def apply = commands.call(dispatcher)

  def reply_to(id) = JSON.parse(store.hget(keys.done, id))

  def turns = store.xrange(keys.copilot).map { JSON.parse(it.fields["json"]) }

  before do
    building("001.00", "tax-rule-dsl")
    start_agents
  end

  describe "stop_plan" do
    before do
      send_command("stop_plan", id: "S1", plan: "1")
      apply
    end

    it "stops both agents and says so" do
      expect(reply_to("S1")).to include("status" => "done", "reason" => "stopped 2 agents on 001.00 and took it off the board")
    end

    it "answers in the conversation as the turn the page waits for" do
      expect(turns).to contain_exactly(include("id" => "S1.1",
        "from" => "copilot",
        "kind" => "text",
        "text" => "done: stopped 2 agents on 001.00 and took it off the board"))
    end

    it "writes no second turn when the command is delivered again" do
      send_command("stop_plan", id: "S1", plan: "1")
      apply
      expect(turns.size).to eq(1)
    end
  end

  describe "restart_plan" do
    it "is refused while the plan has an agent" do
      send_command("restart_plan", id: "R1", plan: "001.00")
      apply
      expect(reply_to("R1")).to include("status" => "refused", "reason" => /already has an agent/)
    end

    it "puts a stopped plan back on the board" do
      send_command("stop_plan", id: "S1", plan: "001.00")
      apply
      executor.release_all(2)
      dispatcher.running.each { it.thread.join(2) }
      dispatcher.tick
      send_command("restart_plan", id: "R2", plan: "001.00")
      apply
      start_agents
      aggregate_failures do
        expect(reply_to("R2")).to include("status" => "done", "reason" => "001.00 restarts at the next tick")
        expect(dispatcher.running.map(&:key)).to include("001.00/luke-backend")
      end
    end
  end

  describe "set_concurrency" do
    it "lowers the limit, stops nobody and records it" do
      send_command("set_concurrency", id: "J1", limit: 1)
      apply
      aggregate_failures do
        expect(reply_to("J1")).to include("status" => "done", "reason" => "concurrency 3 → 1; the run waits for 1 agent to finish")
        expect([runner.jobs, run_state.concurrency, dispatcher.running.size]).to eq([1, 1, 2])
      end
    end

    it "refuses a limit that is not a whole number of at least 1" do
      send_command("set_concurrency", id: "J2", limit: "two")
      apply
      expect(reply_to("J2")).to include("status" => "refused", "reason" => /whole number of at least 1/)
    end
  end

  it "answers a page's command only on replies" do
    OpenLanes::Live.enqueue(store:, keys:, input: { id: "P1", kind: "set_concurrency", payload: { limit: 2 } })
    apply
    expect(turns).to be_empty
  end
end
