# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Extensions, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  let(:ask) { OpenLanes::Plans::PlanState::ExtensionAsk.new(agent: "a", state: :building, round: "1", limit: "time", at:) }

  it "numbers requests, takes an estimate only at its estimate stage, and settles once" do
    section.ask_extension!(ask, { stage: "estimate" })
    expect(section.estimate_extension!("a", 600, nil, at)["estimate"]).to eq(600)
    section.settle_extension!(1, at, { answer: "yes" })
    expect([section.settle_extension!(1, at, { answer: "no" }), section.extensions.first["answer"]]).to eq([nil, "yes"])
  end

  it "reads no estimate argument when no request is waiting at its estimate stage" do
    expect(section.estimate_extension!("a", "soon", nil, at)).to be_nil
  end

  it "amends and spends a request by number" do
    section.ask_extension!(ask, {})
    section.amend_extension!(1, { seconds: 60 })
    section.spend_extension!(1)
    expect(section.extensions.first.values_at("number", "seconds", "spent", "moves")).to eq([1, 60, true, 0])
  end
end
