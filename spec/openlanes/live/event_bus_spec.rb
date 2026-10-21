# frozen_string_literal: true

require "redis-client"
require_relative "../../support/shared_examples/event_bus_contract"

RSpec.describe OpenLanes::Live::EventBus do
  describe OpenLanes::Live::EventBus::MemoryBus do
    subject(:bus) { described_class.new }

    it_behaves_like "an event bus"
  end

  describe OpenLanes::Live::EventBus::RedisBus, :redis do
    subject(:bus) { described_class.new(OpenLanes::Live::Store.new(url:)) }

    let(:url) { TestRedis.url(15) }
    let(:admin) { RedisClient.config(url:).new_client }

    around do |example|
      if begin
        admin.call("PING") == "PONG"
      rescue RedisClient::Error
        false
      end
        admin.call("FLUSHDB")
        example.run
        admin.call("FLUSHDB")
        admin.close
      else
        skip "no Redis answers at #{url}"
      end
    end

    it_behaves_like "an event bus"
  end

  describe ".for" do
    it "wraps a memory store in a MemoryBus" do
      expect(described_class.for(OpenLanes::Live::MemoryStore.new)).to be_a(described_class::MemoryBus)
    end

    it "wraps a Redis store in a RedisBus" do
      expect(described_class.for(OpenLanes::Live::Store.new(url: TestRedis.url(15))))
        .to be_a(described_class::RedisBus)
    end
  end
end
