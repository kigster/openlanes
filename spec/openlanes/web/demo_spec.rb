# frozen_string_literal: true

# The demo engine: it publishes the fixture board for this node and one
# other, and answers commands through the same streams the engine reads.
RSpec.describe OpenLanes::Web::Demo do
  subject(:demo) { described_class.new(store:, keys:, interval: 0.01, clock: -> { at }) }

  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "demo/github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:at) { Time.utc(2026, 10, 13, 9, 30) }
  let(:board) { OpenLanes::Live.board(store:, keys:) }

  def send_command(**command)
    OpenLanes::Live.enqueue(store:, keys:, input: { id: "01CMD#{store.xlen(keys.commands)}", plan: nil, agent: nil, payload: {} }.merge(command))
  end

  def replies = OpenLanes::Live.replies(store:, keys:, after: "0").map(&:last)

  describe "#tick" do
    before { demo.tick }

    it "publishes this node's board and the other machine's" do
      expect([board[:me]["project"], board[:others].map { it.dig("node", "host") }]).to eq(["openlanes", ["ci-runner-2"]])
    end

    it "stamps the snapshot with the time and a new seq" do
      expect(board[:me].values_at("at", "seq")).to eq(["2026-10-13T09:30:00Z", 1])
    end

    it "counts the seq up on every tick" do
      demo.tick
      expect(board[:me]["seq"]).to eq(2)
    end

    it "keeps both snapshots alive only for the snapshot TTL" do
      expect(store.ttl(keys.snapshot)).to be_between(1, OpenLanes::Live::Keys::SNAPSHOT_TTL)
    end
  end

  describe "a command" do
    before { demo.tick }

    context "when it can be applied" do
      before do
        send_command(kind: "hold_blocked", plan: "001.00", payload: { question: "B1" })
        demo.tick
      end

      it "is answered done on the replies stream" do
        expect(replies).to contain_exactly(include("id" => "01CMD0", "status" => "done"))
      end

      it "changes the board" do
        expect(board[:me]["plans"].first["questions"].first["held"]).to be(true)
      end

      it "is recorded in done and acknowledged" do
        expect(store.hget(keys.done, "01CMD0")).to include('"status":"done"')
      end
    end

    context "when it cannot" do
      before do
        send_command(kind: "stop", plan: "001.00", agent: "nobody")
        demo.tick
      end

      it "is answered refused with the engine's reason" do
        expect(replies).to contain_exactly(include("status" => "refused", "reason" => "001.00/nobody is not running"))
      end
    end

    context "when it carries a reason" do
      before do
        send_command(kind: "stop_all")
        demo.tick
      end

      it "is answered done with it" do
        expect(replies.first["reason"]).to eq("stopping 3 agents on dana@studio-mini")
      end
    end

    context "when it is delivered twice" do
      before do
        2.times { store.xadd(keys.commands, { json: JSON.generate(id: "01TWICE", kind: "stop_all", plan: nil, agent: nil, payload: {}) }) }
        demo.tick
      end

      it "is applied once and answered twice with the first reply" do
        expect(replies.map { it.values_at("id", "status", "reason") }.uniq).to eq([["01TWICE", "done", "stopping 3 agents on dana@studio-mini"]])
      end
    end

    context "when it is malformed in the stream" do
      before do
        store.xadd(keys.commands, { json: "{not json" })
        demo.tick
      end

      it "is refused under its stream id" do
        expect(replies).to contain_exactly(include("status" => "refused", "id" => match(/\A\d+-\d+\z/)))
      end
    end
  end

  describe "commands left from an earlier demo" do
    before do
      store.xadd(keys.commands, { json: JSON.generate(id: "01STALE", kind: "stop_all", plan: nil, agent: nil, payload: {}) })
      demo.tick
    end

    it "are not applied to this one's board" do
      expect(replies).to be_empty
    end
  end

  describe "#reset" do
    before do
      demo.tick
      send_command(kind: "answer", plan: "001.00", payload: { question: "B1", text: "yes" })
      demo.tick
      demo.reset
      demo.tick
    end

    it "puts the fixture back, seq still counting up" do
      expect([board[:me]["plans"].first["questions"].size, board[:me]["seq"]]).to eq([1, 3])
    end
  end

  describe "#start and #stop" do
    before do
      demo.start
      sleep 0.05
      demo.stop
    end

    it "publishes while running and takes both snapshots down when stopped" do
      expect([board[:me], board[:others], store.hgetall(keys.nodes)]).to eq([nil, [], {}])
    end
  end

  describe "Redis going away" do
    before { allow(store).to receive(:xgroup_create).and_raise(OpenLanes::Live::Unavailable, "gone") }

    it "logs it and answers nothing" do
      expect(demo.tick).to eq([])
    end

    it "stops without complaint" do
      allow(store).to receive(:del).and_raise(OpenLanes::Live::Unavailable, "gone")
      expect(demo.stop).to be_nil
    end
  end
end
