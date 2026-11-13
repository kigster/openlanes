# frozen_string_literal: true

# A Redis that accepts the connection but stops answering: callers queued
# behind the one that timed out must not each wait out a timeout of their own.
# No Redis needed; the connection is a stand-in that hangs, then fails.
RSpec.describe OpenLanes::Live::Store do
  subject(:store) { described_class.new(url: "redis://127.0.0.1:1/15", timeout: 0.1) }

  let(:entered) { Queue.new }
  let(:release) { Queue.new }
  let(:client) { instance_double(RedisClient, close: nil) }

  before do
    calls = 0
    allow(client).to receive(:call) do
      calls += 1
      next "PONG" unless calls == 1

      entered << true
      release.pop
      raise RedisClient::ReadTimeoutError, "Waited 0.1 seconds"
    end
    store.instance_variable_set(:@client, client)
  end

  # Starts a call that holds the lock until +release+ is fed, and a second
  # caller that queues behind it; returns the second caller's outcome.
  def queued_outcome
    hung = Thread.new { store.ping rescue $ERROR_INFO } # rubocop:disable Style/RescueModifier
    entered.pop
    waiting = Thread.new { store.ping rescue $ERROR_INFO } # rubocop:disable Style/RescueModifier
    Thread.pass until waiting.status == "sleep"
    release << true
    [hung.value, waiting.value]
  end

  it "fails a caller that queued behind a failed call without asking Redis" do
    hung, waiting = queued_outcome
    expect([hung, waiting]).to all(be_a(OpenLanes::Live::Unavailable))
    expect(waiting.message).to include("a call failed while this one waited")
    expect(client).to have_received(:call).once
  end

  it "asks Redis again for a caller that arrives after the failure" do
    queued_outcome
    expect(store.ping).to be(true)
  end
end
