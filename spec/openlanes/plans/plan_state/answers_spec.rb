# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Answers, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  let(:entry) { OpenLanes::Plans::Journal::Entry.new(kind: "question", text: "Which?", ref: "B1", answer: "a") }

  it "writes an answer once" do
    expect([section.answer!("a", entry), section.answer!("a", entry)]).to eq([entry, nil])
  end

  it "names whoever blocked last, by stage or signature" do
    document.update do |data|
      data["stages"] << { "agent" => "early", "status" => "Blocked", "finished_at" => at.iso8601 }
      data["signatures"] << { "agent" => "late", "status" => "Blocked", "at" => (at + 1).iso8601 }
    end
    expect(section.blocked_by).to eq("late")
  end
end
