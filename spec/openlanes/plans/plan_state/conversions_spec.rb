# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Conversions, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  it "records a conversion and recognises its digest" do
    section.conversion!(OpenLanes::Plans::PlanState::Conversion.new(question: "2",
      digest: "d1",
      original: "?",
      model: "m",
      outcome: "converted",
      at:))
    expect([section.converted?("d1"), section.converted?("d2"), section.conversions.first.key?("note")]).to eq([true, false, false])
  end
end
