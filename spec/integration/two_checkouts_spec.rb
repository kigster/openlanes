# frozen_string_literal: true

require_relative "../support/control_room_process"

# Plan 004, B4: two checkouts of one repository, two engines, one Redis. Each
# sees the other as a read-only peer, neither can be told to work on a plan
# the other holds, and no plan is ever claimed by both. The checkouts share an
# `origin`, so Redis knows them as one repository and two nodes.
RSpec.describe "two checkouts on one Redis", :redis do
  let(:url) { ControlRoomProcess.redis_url(10) }
  let(:ordinals) { %w[001.00 002.00 003.00 004.00] }
  let(:roots) { Array.new(2) { ControlRoomProcess.checkout(Dir.mktmpdir("openlanes-two-checkouts")) } }
  let(:rooms) { roots.map { ControlRoomProcess.new(root: it, redis_url: url) } }

  around do |example|
    reason = ControlRoomProcess.unmet(url)
    skip reason if reason

    roots.each do |root|
      builder = PlansFixture::Builder.new(File.join(root, ".plans"))
      ordinals.each { builder.plan(it, :new, "idea-#{it.to_i}", files: { "spec.md" => "# Idea #{it.to_i}\n" }) }
    end
    rooms.each(&:start_engine)
    example.run
  ensure
    rooms&.each(&:stop_all)
    roots&.each { FileUtils.rm_rf(it) }
  end

  def board(room) = JSON.parse(room.get("/api/board").body)

  # Both engines run as one user on one host, so the checkout is what tells
  # their claims apart.
  #
  # @return [String] the `<node>:<checkout>` its claims carry
  def claimant(room) = OpenLanes::Live::Node.current(root: room.root).name

  # @return [Hash{String => String}] ordinal => the node:checkout holding it
  def claims(room)
    room.redis("KEYS", "*:claim:*").to_h { [it.split(":").last, room.redis("GET", it)] }.compact
  end

  def mine(snapshot) = snapshot.to_h.fetch("plans", []).map { it["ordinal"] }

  it "shows each engine the other as a read-only peer" do
    rooms.each do |room|
      peers = room.wait_until(deadline: 15) { board(room)["others"].then { it unless it.empty? } }
      expect(peers.size).to eq(1)
      expect(peers.first.dig("node", "me")).to be(false)
      expect(peers.first.dig("node", "checkout")).not_to eq(board(room).dig("me", "node", "checkout"))
    end
  end

  # Watched for a while, not once: a double claim is a race, and a race
  # shows only across many ticks of both engines.
  #
  # @return [Hash{String => Set<String>}] ordinal => every holder seen
  def watch_claims(seconds)
    a, b = rooms
    seen = Hash.new { |table, ordinal| table[ordinal] = Set.new }
    stop = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < stop
      claims(a).each { |ordinal, holder| seen[ordinal] << holder }
      expect(mine(board(a)["me"]) & mine(board(b)["me"])).to be_empty
      IO.select(nil, nil, nil, 0.1)
    end
    seen
  end

  it "never lets both engines claim one plan" do
    rooms.each { |room| room.wait_until(deadline: 20) { board(room)["me"] } }

    seen = watch_claims(4)

    expect(seen).not_to be_empty
    expect(seen.values).to all(have_attributes(size: 1))
    expect(seen.values.map(&:first) - rooms.map { claimant(it) }).to be_empty
    # The agents the claims were for ran the harness's fake claude, not a real one.
    expect(rooms.sum(&:agent_calls)).to be_positive
  end

  it "refuses a command that would take the peer's plan" do
    ordinal, holder = rooms.first.wait_until(deadline: 20) { claims(rooms.first).first }
    peer = rooms.find { claimant(it) != holder }
    id = "steal-#{ordinal.delete(".")}" # a command id carries no dot
    stream = peer.sse("/api/events")

    expect(peer.post("/api/commands", { id:, kind: "add_plan", payload: { ordinal: } })).to be_a(Net::HTTPAccepted)
    reply = stream.wait_for(deadline: 10) { it.name == "reply" && it.data["id"] == id }

    expect(reply.data).to include("status" => "refused")
    expect(reply.data["reason"]).to include("#{ordinal} is being worked on")
    expect(claims(peer)[ordinal]).to eq(holder)
  end
end
