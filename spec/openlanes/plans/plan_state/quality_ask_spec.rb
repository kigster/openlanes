# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::QualityAsk, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  it "keeps the first ask, and settles it once" do
    section.ask_quality!(at)
    section.ask_quality!(at + 1)
    section.settle_quality_ask!(:mvp, "kig", at + 2)
    expect([section.quality_ask["asked_at"], section.settle_quality_ask!("high", "x", at)]).to eq([at.iso8601, nil])
  end
end
