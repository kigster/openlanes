# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::LastKnown, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  it "refuses an agent name that is not one token, and reads nothing before a record" do
    expect { section.record_last_known("a b", nil) }.to raise_error(OpenLanes::Error, /resume record needs an agent name/)
    expect([section.last_known("a"), section.last_known_states]).to eq([nil, {}])
  end
end
