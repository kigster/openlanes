# frozen_string_literal: true

require_relative "store_examples"

# The real Redis, on database 15 and flushed around every example, so a
# developer's own keys in database 0 are never touched. Skipped where no
# Redis answers, which is CI unless it starts one.
RSpec.describe OpenLanes::Live::Store, :redis do
  subject(:store) { described_class.new(url: url) }

  let(:url) { TestRedis.url(15) }
  let(:admin) { RedisClient.config(url:).new_client }

  # Asked through the client, not `redis-cli`: CI's Ruby image runs a Redis
  # beside it but has no redis-cli, so every example here skipped there, and
  # any change to store.rb failed the changed-file coverage gate.
  def answers?
    admin.call("PING") == "PONG"
  rescue RedisClient::Error
    false
  end

  around do |example|
    if answers?
      admin.call("FLUSHDB")
      example.run
      admin.call("FLUSHDB")
      admin.close
    else
      skip "no Redis answers at #{url}"
    end
  end

  it_behaves_like "a live store"

  # #59: a Redis restarted empty has no consumer group; Commands makes it again.
  it "says a missing consumer group is missing, not that Redis is unreachable" do
    expect { store.xreadgroup("gone", "engine", "me") }.to raise_error(OpenLanes::Live::GroupMissing, /NOGROUP/)
  end

  # The engine pings from its tick while agent threads publish through the
  # same store. RedisClient is not thread-safe: unserialized, one thread's
  # call found the other's buffer mid-write and raised "can't modify string;
  # temporarily locked".
  it "answers callers on several threads at once" do
    threads = Array.new(8) { |n| Thread.new { 200.times { |i| store.set("k#{n}", i.to_s) && store.ping } } }
    expect { threads.each(&:join) }.not_to raise_error
  end

  it "waits for an entry when asked to block, and returns empty when none comes" do
    expect(store.xread("s", id: "$", block: 20)).to eq([])
  end

  context "when a pending entry's stream is deleted and made again" do
    before do
      store.xgroup_create("cmd", "engine")
      store.xadd("cmd", { json: "gone" })
      store.xreadgroup("cmd", "engine", "me")
      store.del("cmd")
      store.xgroup_create("cmd", "engine")
    end

    it "has nothing pending" do
      expect(store.xreadgroup("cmd", "engine", "me", id: "0")).to eq([])
    end
  end

  it "passes on a command Redis refuses, which is a bug rather than an outage" do
    store.set("k", "v")
    expect { store.hset("k", "f", "v") }.to raise_error(RedisClient::CommandError, /WRONGTYPE/)
  end

  context "when nothing listens at the address" do
    subject(:store) { described_class.new(url: "redis://:hunter2@127.0.0.1:1/15", timeout: 0.2) }

    it "is Unavailable, with the password masked" do
      expect { store.ping }.to raise_error(OpenLanes::Live::Unavailable, %r{redis://:\*\*\*@127\.0\.0\.1:1})
    end
  end
end
