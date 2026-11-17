# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Memory, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  let(:entry) { OpenLanes::Plans::Journal::Entry.new(kind: "note", text: "one") }

  it "starts the next journal round and refuses an override that points ahead" do
    ahead = OpenLanes::Plans::Journal::Entry.new(kind: "override", text: "two", overrides: 5)
    number, rejected = section.journal!("a", [entry, ahead], nil, { "round" => 1 })
    expect([number, rejected.size, section.journal("a").first.entries.size]).to eq([1, 1, 1])
  end

  it "refuses an agent name that is not one token" do
    expect { section.journal!("a b", [], nil, {}) }.to raise_error(OpenLanes::Error, /journal needs an agent name/)
  end
end
