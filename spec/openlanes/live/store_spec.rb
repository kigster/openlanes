# frozen_string_literal: true

require_relative "store_examples"

# The real Redis, on database 15 and flushed around every example, so a
# developer's own keys in database 0 are never touched. Skipped where no
# Redis answers, which is CI unless it starts one.
RSpec.describe OpenLanes::Live::Store, :redis do
  subject(:store) { described_class.new(url: url) }

  let(:url) { TestRedis.url(15) }
  let(:admin) { RedisClient.config(url:).new_client }

  around do |example|
    if system("redis-cli", "-u", url, "ping", out: File::NULL, err: File::NULL)
      admin.call("FLUSHDB")
      example.run
      admin.call("FLUSHDB")
      admin.close
    else
      skip "no Redis answers at #{url}"
    end
  end

  it_behaves_like "a live store"

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
