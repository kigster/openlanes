# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Dispatcher::Rename::Verdicts do
  def entry(note) = Struct.new(:note).new(note)

  it "reads each verdict a closing note can carry" do
    notes = ["approved", "verified on disk", "slop", "needs a rewrite", "product question", "all good"]
    expect(notes.map { described_class.of(entry(it)) }).to eq([:approved, :verified, :slop, :slop, :product, nil])
  end

  it "takes 'nothing to reject' as no rejection" do
    expect(described_class.of(entry("nothing to reject, approved"))).to eq(:approved)
  end

  it "sends a rejection and slop to their own states, anything else onward or to the pair's hold" do
    agent = Struct.new(:holds_at, :advances_to).new(:building_ui, :ready_for_review)
    expect([described_class.target(agent, :rejected, false), described_class.target(agent, :slop, true),
            described_class.target(agent, nil, false), described_class.target(agent, nil, true)])
      .to eq(%i[rejected rewrite ready_for_review building_ui])
  end
end
