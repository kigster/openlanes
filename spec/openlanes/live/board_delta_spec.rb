# frozen_string_literal: true

RSpec.describe OpenLanes::Live::BoardDelta do
  def plan(ordinal, tokens) = { "ordinal" => ordinal, "up" => tokens, "cars" => [] }

  def snapshot(id, seq, plans) = { "seq" => seq, "node" => { "id" => id, "checkout" => "~/w" }, "plans" => plans }

  let(:before) { { me: snapshot("a", 1, [plan("001.00", 10), plan("002.00", 5)]), others: [snapshot("b", 1, [])] } }

  it "upserts only the plan and node that changed" do
    after = { me: snapshot("a", 2, [plan("001.00", 20), plan("002.00", 5)]), others: [snapshot("b", 1, [])] }
    delta = described_class.diff(before, after)
    aggregate_failures do
      expect(delta[:upsert].map { it[:key] }).to eq(%w[node/a/~/w plan/a/~/w/001.00])
      expect(delta[:upsert].last[:value]).to eq(plan("001.00", 20))
      expect(delta[:remove]).to eq([])
    end
  end

  it "keeps each node's plan order beside its snapshot, without the plans" do
    node = described_class.entries(before)["node/a/~/w"]
    expect([node.key?("plans"), node["plan_order"]]).to eq([false, %w[001.00 002.00]])
  end

  it "removes a plan that left and a node that went" do
    after = { me: snapshot("a", 2, [plan("001.00", 10)]), others: [] }
    expect(described_class.diff(before, after)[:remove]).to eq(%w[plan/a/~/w/002.00 node/b/~/w])
  end

  it "is empty between equal boards, whatever the key types" do
    symbols = JSON.parse(JSON.generate(before), symbolize_names: true)
    expect(described_class.diff(before, symbols)).to eq(upsert: [], remove: [])
  end

  describe OpenLanes::Live::BoardDelta::Stream do
    let(:stream) { described_class.new }
    let(:wide) { { me: snapshot("a", 2, [plan("001.00", 10).merge("title" => "x" * 400), plan("002.00", 5)]), others: [snapshot("b", 1, [])] } }

    it "sends the board whole when the page holds none" do
      expect(stream.next(before)).to eq(["board", before.merge(version: 1)])
    end

    it "numbers each frame, and sends a delta that names the version it applies onto" do
      stream.next(wide)
      moved = { me: snapshot("a", 3, [plan("001.00", 11).merge("title" => "x" * 400), plan("002.00", 5)]), others: [snapshot("b", 1, [])] }
      event, delta = stream.next(moved)
      expect([event, delta.slice(:base, :version), delta[:upsert].map { it[:key] }])
        .to eq(["board_delta", { base: 1, version: 2 }, %w[node/a/~/w plan/a/~/w/001.00]])
    end

    it "sends the board whole when the delta would not be smaller" do
      stream.next(before)
      tiny = { me: snapshot("c", 1, []), others: [] }
      expect(stream.next(tiny).first).to eq("board")
    end

    it "serialises an entry once, however many ticks leave it unchanged" do
      stream.next(wide)
      allow(JSON).to receive(:generate).and_call_original
      moved = { me: snapshot("a", 3, [plan("001.00", 10).merge("title" => "x" * 400), plan("002.00", 6)]), others: [snapshot("b", 1, [])] }
      stream.next(moved)
      # One pass to flatten the new board, one to measure the plan that moved and one for its node: never the whole board again.
      expect(JSON).to have_received(:generate).exactly(3).times
    end
  end
end
