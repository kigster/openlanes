# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Signatures, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  def sign(**fields) = section.sign!(OpenLanes::Plans::PlanState::Signature.new(agent: "backend-coder", round: 1, at:, **fields))

  it "writes a signature and reads it back as ledger entries, two lines each" do
    sign(status: "Completed", next_agent: "staff-reviewer")
    reading = section.ledger
    expect([reading.entries.first.line, reading.handoffs.first.line, reading.handoffs.first.next]).to eq([1, 2, "staff-reviewer"])
  end

  it "refuses a handoff after anything but Completed" do
    expect { sign(status: "Started", next_agent: "x") }.to raise_error(OpenLanes::Error, /only a Completed/)
  end
end
