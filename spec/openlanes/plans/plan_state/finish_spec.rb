# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Finish, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  it "lets a merge replace an approval, and nothing replace a merge" do
    section.finish!(:approved, at)
    section.finish!("merged", at + 1)
    expect(section.finish!("approved", at + 2)).to eq(OpenLanes::Plans::PlanState::Finished.new(kind: "merged", at: at + 1))
  end

  it "refuses a kind it does not know, and forgets on unfinish" do
    expect { section.finish!("abandoned", at) }.to raise_error(OpenLanes::Error, /approved or merged/)
    section.finish!("approved", at)
    section.unfinish!
    expect(section.finished).to be_nil
  end
end
