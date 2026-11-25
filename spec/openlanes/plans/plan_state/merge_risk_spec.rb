# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::MergeRisk, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  it "keeps verdicts for this visit only, with the siblings rebased" do
    section.assess!({ 12 => :low }, at)
    section.rebased!(13, at)
    expect(section.merge_risk.values_at("verdicts", "rebased")).to eq([{ "12" => "low" }, { "13" => at.iso8601 }])
    document.update { it["moves"] = 1 }
    expect(section.merge_risk).to be_nil
  end
end
