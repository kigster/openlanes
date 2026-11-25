# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::LockRecord, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  it "keeps the first time the lock was taken, and forgets it on release" do
    section.take_global_lock!(at)
    expect(section.take_global_lock!(at + 60)).to eq(at)
    section.release_global_lock!
    expect(section.global_lock_taken_at).to be_nil
  end
end
