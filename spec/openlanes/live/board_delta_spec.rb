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

  describe ".frame" do
    it "sends the board whole when the page holds none" do
      expect(described_class.frame(nil, before, 1)).to eq(["board", before.merge(version: 1)])
    end

    it "sends the board whole when the delta would not be smaller" do
      tiny = { me: snapshot("c", 1, []), others: [] }
      expect(described_class.frame(before, tiny, 2).first).to eq("board")
    end
  end

  describe OpenLanes::Live::BoardDelta::Stream do
    it "numbers each frame, the first whole" do
      stream = described_class.new
      after = { me: snapshot("a", 2, [plan("001.00", 10).merge("title" => "x" * 400), plan("002.00", 5)]), others: [snapshot("b", 1, [])] }
      expect([stream.next(after).first, stream.next(after).last.slice(:base, :version)]).to eq(["board", { base: 1, version: 2 }])
    end
  end
end
