# frozen_string_literal: true

require_relative "../live/live_context"
require_relative "../../support/redis_server"

# Issue #59, reproduced: Redis restarts empty between two ticks (no AOF, the
# RDB snapshot older than the commands group, or none at all). The client
# reconnects without a word, so nothing trips an outage, and the next
# XREADGROUP on the commands stream raised NOGROUP, a RedisClient::CommandError
# that no rescue in the tick caught. The run ended. `Commands#read` now makes
# the group again within the same tick.
RSpec.describe "Redis restarting empty under a running engine", :tree do
  include_context "with a live run"

  let(:server) { RedisServer.new.start }
  let(:store) { OpenLanes::Live::Store.new(url: server.url, timeout: 0.5) }
  let(:session) do
    OpenLanes::Live::Session.new(store:, root: plans_root, tree:, agents:, node:, repo: "github.com/example/openlanes")
  end
  let(:dispatcher) { OpenLanes::Engine::Dispatcher.new(runner:, sleeper: ->(_) {}, on_board: session.on_board) }

  before do
    skip RedisServer.missing if RedisServer.missing
    allow(OpenLanes::UI).to receive(:log)
    building("001.00", "tax-rule-dsl")
    session.attach(dispatcher)
  end

  after { server.destroy }

  def restart_empty
    server.stop
    server.wipe
    server.start
  end

  it "keeps ticking, and makes the commands group again" do
    start_agents
    restart_empty
    expect { 2.times { dispatcher.tick } }.not_to raise_error
    expect(store.xreadgroup(session.keys.commands, OpenLanes::Live::Keys::GROUP, node.name, id: "0")).to eq([])
  end
end
