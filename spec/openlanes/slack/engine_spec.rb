# frozen_string_literal: true

require_relative "../live/live_context"
require_relative "../../support/fake_slack"

# The whole way round, with only Slack itself faked: a blocked plan's
# question reaches the channel off the engine's own snapshot, and a click
# there ends as a signed answer in `blocked.md`, written by the same
# command the control room sends.
RSpec.describe "A run that asks its questions in Slack", :tree do
  include_context "with a live run"

  let(:slack) { FakeSlack.new }
  let(:bridge) do
    room = OpenLanes::Slack::Room.new(api: slack.api, channel: "#questions")
    OpenLanes::Slack::Bridge.new(room:, outbox: OpenLanes::Slack::Outbox.new(store:, keys:), interval: 3600)
  end
  let(:session) do
    OpenLanes::Live::Session.new(store:,
      root: File.dirname(plans_root),
      tree:,
      agents:,
      node:,
      repo: keys.repo,
      slack: ->(**) { bridge })
  end
  let(:dispatcher) { OpenLanes::Engine::Dispatcher.new(runner:, sleeper: ->(_) {}, on_board: session.on_board, stay: true) }

  before do
    blocked("002.00", "rebase", "# Blocked\n\n## B1 Rebase\nanswers: yes, no\n\nShould I rebase?\n")
    session.attach(dispatcher)
  end

  after { session.close }

  it "posts the question as a poll and writes the answer clicked there into blocked.md" do
    dispatcher.tick
    bridge.cycle
    expect(slack.text_of(slack.posts.first)).to include("002.00", "B1 Rebase", "Should I rebase?", ":one:  yes\n:two:  no")

    slack.click(slack.posts.first, "one")
    bridge.cycle
    dispatcher.tick

    expect(File.read(File.join(path_of("002.00"), "blocked.md")))
      .to match(/## A1\n\nyes\n\n\(via Slack, Dana Okafor\)\n\nAnswered by dana on \d{4}-\d\d-\d\d\n<!-- cmd:slack-\h{32} -->/)
  end
end
