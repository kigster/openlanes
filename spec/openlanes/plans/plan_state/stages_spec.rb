# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Stages, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  it "updates the latest record of an agent's round, and appends one on reset" do
    section.stage!("backend-coder", 1, false, { status: "Started", from: "planned" })
    section.stage!("backend-coder", 1, false, { status: "Completed", to: "review" })
    section.stage!("backend-coder", 1, true, { status: "Started" })
    expect(section.stages.map { it.values_at("status", "visit", "moves") }).to eq([["Completed", 0, 0], ["Started", nil, nil]])
  end

  it "counts a move only when the state changes" do
    %i[building building review].each { section.state!(it) }
    expect([section.state, section.moves]).to eq(["review", 2])
  end

  it "lifts a halt until the time given, and no longer" do
    section.resume_anyway!(at + 3600)
    expect([section.resumed?(at), section.resumed?(at + 7200), section.resume_until]).to eq([true, false, at + 3600])
  end
end
