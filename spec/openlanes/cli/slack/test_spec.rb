# frozen_string_literal: true

require_relative "../../../support/fake_slack"

RSpec.describe OpenLanes::CLI::Slack::Test do
  subject(:command) { described_class.new }

  let(:slack) { FakeSlack.new }
  let(:room) { OpenLanes::Slack::Room.new(api: slack.api, channel: "#questions") }

  def run(**)
    out, err, status = CapturedStream.capture { command.call(timeout: 0, **) }
    [strip_ansi(out), strip_ansi(err), status.to_i]
  end

  before { allow(OpenLanes::Slack).to receive(:room).and_return(room) }

  it "posts a sample poll and prints who answered and what, on STDOUT" do
    allow(room).to receive(:decorate).and_wrap_original do |original, ref, poll|
      original.call(ref, poll)
      slack.click(ref.ts, "one")
    end
    out, err, status = run

    expect(status).to eq(0)
    expect(out).to eq("Dana Okafor\ta) Yes, I can see this\n")
    expect(err).to include("Workspace Acme (T0ACME), posting as openlanes to #questions")
    expect(slack.text_of(slack.posts.first)).to include("Is the Slack connection working?").and end_with("Answered by <@UDANA>: Yes, I can see this")
  end

  it "says which scopes read an answer when nobody's arrives in time" do
    out, err, status = run

    expect([out, status]).to eq(["", 75])
    expect(err).to include("nobody answered it in time", "reactions:read", "channels:history")
    expect(slack.text_of(slack.posts.first)).to end_with("Nobody answered in time.")
  end

  it "waits between looks until the time is up" do
    allow(Kernel).to receive(:sleep) { slack.click(slack.posts.first, "two") }
    out, = run(timeout: 60)

    expect(out).to eq("Dana Okafor\tb) No\n")
    expect(Kernel).to have_received(:sleep).with(OpenLanes::Slack::DEFAULT_INTERVAL).once
  end

  it "reports a misconfiguration as a refusal, not a backtrace" do
    allow(OpenLanes::Slack).to receive(:room).and_raise(OpenLanes::Error, "no Slack channel")
    _, err, status = run

    expect(status).to eq(69)
    expect(err).to include("no Slack channel")
  end
end
