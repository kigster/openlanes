# frozen_string_literal: true

require_relative "live_context"

RSpec.describe OpenLanes::Live::Publisher, :tree do
  subject(:publisher) do
    described_class.new(store:,
      keys:,
      node:,
      tree:,
      agents:,
      project: "openlanes",
      claims:,
      run_state:,
      clock: -> { Time.utc(2026, 10, 13, 9) })
  end

  include_context "with a live run"

  before { building("001.00", "tax-rule-dsl") }

  after { publisher.close }

  it "writes the snapshot for thirty seconds, appends it to the board, and beats the heart" do
    publisher.call(dispatcher.board)
    aggregate_failures do
      expect(JSON.parse(store.get(keys.snapshot))["seq"]).to eq(1)
      expect(store.ttl(keys.snapshot)).to be_between(29, 30)
      expect(store.xrange(keys.board).map { it.fields["seq"] }).to eq(["1"])
      expect(JSON.parse(store.hget(keys.nodes, node.name))).to include("user" => "dana", "heartbeat_at" => "2026-10-13T09:00:00Z")
    end
  end

  it "names the Redis it publishes through, which is the one the page shows" do
    publisher.call(dispatcher.board)
    expect(JSON.parse(store.get(keys.snapshot))["redis_url"]).to eq(store.url)
  end

  it "counts on from the board stream, so a restarted engine never repeats a seq" do
    store.xadd(keys.board, { seq: 41, json: "{}" })
    expect(publisher.call(dispatcher.board)[:seq]).to eq(42)
  end

  it "is the runner's on_board" do
    publisher.to_proc.call(dispatcher.board)
    expect(publisher.seq).to eq(1)
  end

  it "renews the claims it holds" do
    claims.claim("001.00")
    store.expire(keys.claim("001.00"), 5)
    publisher.call(dispatcher.board)
    expect(store.ttl(keys.claim("001.00"))).to be > 80
  end

  describe "a claim another machine took" do
    let(:lost) { [] }

    before do
      claims.claim("001.00")
      store.set(keys.claim("001.00"), "ffffffffffffffffffffffff:000000000000")
      publisher.on_lost { lost.concat(it) }
      allow(OpenLanes::UI).to receive(:log)
      publisher.call(dispatcher.board)
    end

    it "is handed to whoever stops its agents, and logged" do
      aggregate_failures do
        expect(lost).to eq(%w[001.00])
        expect(OpenLanes::UI).to have_received(:log).with("claims lost to another machine: 001.00; stopping their agents")
      end
    end
  end

  it "reports a missing Redis once, and carries on" do
    allow(store).to receive(:multi).and_raise(OpenLanes::Live::Unavailable, "gone")
    allow(OpenLanes::UI).to receive(:log)
    2.times { publisher.call(dispatcher.board) }
    expect(OpenLanes::UI).to have_received(:log).with("board not published: gone").once
  end

  describe "the log" do
    before { publisher.listen }

    it "keeps what UI.log says, marking problems as warnings" do
      OpenLanes::UI.log("started", plan: "001.00", agent: "luke-backend")
      OpenLanes::UI.log("failed: no ledger line", plan: "001.00")
      expect(publisher.log).to eq([
                                    { at: "2026-10-13T09:00:00Z", source: "luke-backend", level: "info", text: "started", plan: "001.00" },
                                    { at: "2026-10-13T09:00:00Z", source: "engine", level: "warn", text: "failed: no ledger line", plan: "001.00" }
                                  ])
    end

    it "keeps only the latest lines" do
      (described_class::LOG_LINES + 5).times { |i| publisher.hear("line #{i}") }
      expect([publisher.log.size, publisher.log.first[:text]]).to eq([described_class::LOG_LINES, "line 5"])
    end

    it "stops hearing once closed" do
      publisher.close
      OpenLanes::UI.log("after")
      expect(publisher.log).to eq([])
    end
  end
end
