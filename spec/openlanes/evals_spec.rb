# frozen_string_literal: true

RSpec.describe OpenLanes::Evals, :tree do
  let(:kase) { described_class.cases.find { it.id == "research-fast" } }

  it "loads the shipped cases by default" do
    expect(described_class.cases.map(&:to_s)).to include("leah-researcher/research-fast")
  end

  it "scores nothing for a recording the case does not ship" do
    expect(described_class.score_recording(kase, :flaky)).to be_nil
  end

  it "scores any folder against a case" do
    expect(described_class.score(kase, folder: plans_root).passed?).to be(false)
  end
end
