# frozen_string_literal: true

require "json"
require "rack/test"
require_relative "../live/live_context"

# 062.00 B5: the dollar cap end to end. A real `.plans` tree, a real event
# log on disk with priced runs, the real dispatcher and budget, and the
# snapshot read back through the web app's own route. The executor is the
# held fake, the only double, since no coding CLI may really start.
RSpec.describe "Plan budget", :tree do
  include Rack::Test::Methods

  include_context "with a live run"

  let(:log_dir) { File.join(File.dirname(plans_root), "events") }
  let(:budget) do
    OpenLanes::Engine::Budget.new(cap: -> { 5.0 }, events: -> { OpenLanes::Events.log(log_dir).events })
  end
  let(:dispatcher) { OpenLanes::Engine::Dispatcher.new(runner:, sleeper: ->(_) {}, budget:) }
  let(:context) do
    OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store),
      keys:,
      plans_dir: plans_root,
      url: "memory://",
      dist: plans_root,
      node:,
      lifetime: 0.2,
      copilot: OpenLanes::Web::Demo::COPILOT,
      background: ->(&) {})
  end
  let(:app) { OpenLanes::Web.app(context) }

  def spent(ordinal, cost, id)
    OpenLanes::Events::Event.new(event_id: id,
      kind: "agent_finished",
      at: Time.now,
      plan: ordinal,
      agent: "backend-coder",
      payload: { "round" => 1, "status" => "Completed", "cost_usd" => cost })
  end

  # What the page is given: the snapshot as the publisher builds it, read
  # back through `/api/board`. The board names both plans, as a run that
  # had started 001.00 before it crossed its cap would.
  def page_plans
    store.set(keys.snapshot, JSON.generate(snapshot))
    header "Host", "127.0.0.1:11000"
    get "/api/board"
    JSON.parse(last_response.body).dig("me", "plans").to_h { [it["ordinal"], it] }
  end

  def snapshot
    OpenLanes::Live::Snapshot.new(board: dispatcher.board.with(plans: %w[001.00 002.00]),
      tree: tree.reload,
      agents:,
      node:,
      repo: keys.repo,
      project: "openlanes",
      seq: 1,
      claims:,
      run_state:,
      budget:).to_h
  end

  before do
    building("001.00", "spendy")
    building("002.00", "thrifty")
    FileUtils.mkdir_p(log_dir)
    lines = [spent("001.00", 3.5, "a"), spent("001.00", 2.25, "b"), spent("002.00", 1.0, "c"), spent("002.00", nil, "d")]
    File.write(File.join(log_dir, "node.jsonl"), lines.map(&:to_json).join("\n") << "\n")
  end

  after do
    executor.release_all
    dispatcher.running.each { it.thread.join(2) }
  end

  it "holds the over-cap plan, assigns the other, and the page shows both plans' spend" do
    start_agents

    aggregate_failures do
      expect(executor.calls.map { it.split("/").first }.uniq).to eq(%w[002.00])
      expect(dispatcher.send(:budget_holds)).to eq("001.00" => "over budget: $5.75 of $5.00")
      plans = page_plans
      expect(plans["001.00"]["spend"]).to eq("usd" => 5.75, "cap" => 5.0, "over" => true, "unpriced_runs" => 0)
      expect(plans["002.00"]["spend"]).to eq("usd" => 1.0, "cap" => 5.0, "over" => false, "unpriced_runs" => 1)
    end
  end
end
