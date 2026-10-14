# frozen_string_literal: true

RSpec.describe OpenLanes::Live::Stations do
  let(:spine) do
    walk = [:new]
    walk << OpenLanes::Plans::StateMachine::SPINE[walk.last] while OpenLanes::Plans::StateMachine::SPINE[walk.last]
    walk
  end

  it "gives every state on the spine a stop, in spine order" do
    expect(spine.map { described_class.key_for(it) }.chunk_while { |a, b| a == b }.map(&:first))
      .to eq(described_class::GROUPS.map(&:first))
  end

  it "keys every stop but the last by a state on the spine" do
    expect(described_class::GROUPS.map(&:first).first(6)).to all(satisfy { spine.include?(it) })
  end

  it "shows a state off the spine where the spine takes it next" do
    expect(%i[shit rolled_back].map { described_class.key_for(it) }).to eq(%i[building in_review])
  end

  it "shows a rejected plan at Building, where luke and rey rework it" do
    expect(described_class.key_for(:rejected, before: :in_review)).to eq(:building)
  end

  it "shows a blocked plan where it was, or at the first stop when nobody knows" do
    expect([described_class.key_for(:blocked, before: :building_ui), described_class.key_for(:blocked)]).to eq(%i[building_ui new])
  end

  describe "the building stop" do
    subject(:building) { described_class.all(OpenLanes::Agents::Registry.new).find { it.key == :building } }

    it "reads its agents from their handles" do
      aggregate_failures do
        expect(building.agents).to contain_exactly("luke-backend", "r2d2-mechanic", "rey-frontend")
        expect(building.wire).to eq(key: "building", label: "Building", agents: building.agents)
      end
    end
  end
end
