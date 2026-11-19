# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Holds, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  it "holds the journal written so far, and forgets it" do
    expect(section.hold!("a", "s1")).to eq(OpenLanes::Plans::Journal::Held.new(session: "s1", through: 0))
    section.forget_held!("a")
    expect(section.held("a")).to be_nil
  end
end
