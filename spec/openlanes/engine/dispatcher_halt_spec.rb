# frozen_string_literal: true

require_relative "../live/live_context"

# A 💣 that appears mid-run stops new work, not work under way: the agent
# already running is joined when it finishes, never killed. The sweep runs
# whenever a slot is free to fill, so the bomb lands before the next start.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

  def backdate_block(days)
    OpenLanes::Plans::PlanState.for(path_of("001.00")).update do |data|
      data["signatures"] << { "at" => (Time.now - (days * 86_400)).iso8601, "agent" => "luke-backend",
                              "status" => "Blocked", "round" => 1 }
    end
  end

  before do
    blocked("001.00", "feed", "## B1 Which feed?\n")
    building("002.00", "consumer", files: { "spec.md" => needs("001.00") })
    building("003.00", "other")
    building("004.00", "later")
    backdate_block(2)
  end

  let(:runner) do
    OpenLanes::Engine::Runner.new(tree:, executor:, agents:, isolation: :shared, claims:, sleeper: ->(_) {})
  end

  it "lets the running agent finish and starts nobody after the halt" do
    start_agents
    first = dispatcher.running.map(&:key)
    expect(first).not_to be_empty

    backdate_block(8)
    dispatcher.tick

    aggregate_failures do
      expect(dispatcher.running.map(&:key)).to eq(first)
      expect(dispatcher.running.map { it.thread.alive? }).to all(be(true))
    end

    executor.release_all
    dispatcher.running.each { it.thread.join(2) }
    3.times { dispatcher.tick }

    aggregate_failures do
      expect(tree.reload.find("001.00").status.key).to eq(:bomb)
      expect(dispatcher.running).to be_empty
      expect(executor.calls).to eq(first)
      expect(dispatcher).to be_done
    end
  end

  it "says it is halted, and on which plan, when it idles" do
    backdate_block(8)
    dispatcher.tick

    expect(dispatcher.send(:idle_reason, runner.in_scope)).to include("halted by 💣 001.00")
  end
end
