# frozen_string_literal: true

# No Redis here: the pub/sub connection is a fake that answers the way
# redis-client does, which hands a refused command back as an error object
# instead of raising it.
RSpec.describe OpenLanes::Live::Subscriber do
  let(:url) { "redis://chat:secret@localhost:6379/3" }
  let(:events) { [] }
  let(:closed) { [] }
  let(:pubsub) do
    queue = events
    shut = closed
    Class.new do
      define_method(:call) { |*| nil }
      define_method(:close) { shut << true }
      define_method(:next_event) do |_timeout|
        event = queue.shift
        raise event if event.is_a?(Class) && event <= RedisClient::Error

        event
      end
    end.new
  end
  let(:pattern) { "openlanes:github.com/acme/widgets:chat:3:room:*" }

  before do
    client = instance_double(RedisClient, pubsub:)
    config = instance_double(RedisClient::Config, new_client: client)
    allow(RedisClient).to receive(:config).and_return(config)
  end

  def subscribe = described_class.new(url:, channels: ["inbox"], patterns: [pattern], timeout: 0.01)

  it "subscribes once both subscriptions are confirmed, and reads either kind of message" do
    events.push(%w[subscribe inbox 1], ["psubscribe", pattern, 2], %w[message inbox hi], ["pmessage", pattern, "room:1", "yo"])
    subscriber = subscribe
    expect([subscriber.next_message(0), subscriber.next_message(0), subscriber.next_message(0)]).to eq([%w[inbox hi], %w[room:1 yo], nil])
  end

  it "turns a refused PSUBSCRIBE into Unavailable, with the password masked" do
    events.push(%w[subscribe inbox 1], RedisClient::CommandError.parse("NOPERM User chat has no permissions to access one of the channels"))
    expect { subscribe }.to raise_error(OpenLanes::Live::Unavailable) { |e|
      expect([e.message, e.message.include?("secret")]).to match([/unavailable: NOPERM User chat/, false])
    }
  end

  it "closes the connection a refused subscription leaves behind, since no caller ever holds it" do
    events.push(%w[subscribe inbox 1], RedisClient::CommandError.parse("NOPERM User chat has no permissions to access one of the channels"))
    expect { subscribe }.to raise_error(OpenLanes::Live::Unavailable)
    expect(closed).to eq([true])
  end

  it "closes the connection when Redis never confirms the subscription" do
    events.push(%w[subscribe inbox 1])
    expect { subscribe }.to raise_error(OpenLanes::Live::Unavailable)
    expect(closed).to eq([true])
  end

  it "turns a dropped connection into Unavailable while it waits for a message" do
    events.push(%w[subscribe inbox 1], ["psubscribe", pattern, 2], RedisClient::ConnectionError)
    subscriber = subscribe
    expect { subscriber.next_message(0) }.to raise_error(OpenLanes::Live::Unavailable, /unavailable: RedisClient::ConnectionError/)
  end

  it "says so when Redis never confirms the subscription" do
    events.push(%w[subscribe inbox 1])
    expect { subscribe }.to raise_error(OpenLanes::Live::Unavailable, /did not confirm a subscription/)
  end
end
