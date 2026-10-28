# frozen_string_literal: true

RSpec.describe OpenLanes::Live::Keys do
  subject(:keys) { described_class.new(repo: "github.com/o/n", node: "abc:def") }

  it "lays out every key as contract.md does" do
    expect([keys.nodes, keys.snapshot, keys.board, keys.commands, keys.replies, keys.done, keys.claim("004.00")])
      .to eq(%w[openlanes:github.com/o/n:nodes openlanes:github.com/o/n:abc:def:snapshot
                openlanes:github.com/o/n:abc:def:board openlanes:github.com/o/n:abc:def:commands
                openlanes:github.com/o/n:abc:def:replies openlanes:github.com/o/n:abc:def:done
                openlanes:github.com/o/n:claim:004.00])
  end

  it "keeps the adapter probes per machine, not per checkout" do
    machine = keys.node.split(":").first
    expect([keys.adapters, keys.adapters_lock]).to eq(["#{keys.base}:adapters:#{machine}", "#{keys.base}:adapters:#{machine}:lock"])
  end

  it "keeps the run state in a hash of its own, per node" do
    expect([keys.run, keys.run("x:y")]).to eq(%w[openlanes:github.com/o/n:abc:def:run openlanes:github.com/o/n:x:y:run])
  end

  it "names another node's keys through the same methods" do
    expect([keys.snapshot("x:y"), keys.board("x:y")]).to eq(%w[openlanes:github.com/o/n:x:y:snapshot openlanes:github.com/o/n:x:y:board])
  end

  it "puts the Redis database in every chat channel, since pub/sub reaches every database" do
    expect([keys.chat_room("c1", db: 13), keys.chat_inbox("m1", db: 13), keys.chat_rooms(db: 13), keys.chat_room("c1", db: 0)])
      .to eq(%w[openlanes:github.com/o/n:chat:13:room:c1 openlanes:github.com/o/n:chat:13:machine:m1
                openlanes:github.com/o/n:chat:13:room:* openlanes:github.com/o/n:chat:0:room:c1])
  end

  it "keeps an invite's answer as a key, which a database does separate" do
    expect(keys.chat_answer("i1")).to eq("openlanes:github.com/o/n:chat:invite:i1")
  end
end
