# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Rulings, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  it "writes a ruling in the key order state.json carries, dropping empty fields" do
    ruling = OpenLanes::Plans::PlanState::Ruling.new(kind: :cap,
      pr: "7",
      round: nil,
      outcome: "struck",
      winner: nil,
      findings: { struck: [:F1], critical: [] },
      reason: "out of scope",
      trigger: "appeal",
      at:)
    expect(section.rule!(ruling).keys).to eq(%w[at kind pr outcome findings reason trigger])
    expect(section.rulings.first["findings"]).to eq("struck" => ["F1"], "critical" => [])
  end
end
