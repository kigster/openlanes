# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Messages, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  def send_message(after: 0, command: nil)
    section.message!(OpenLanes::Plans::PlanState::Message.new(from: "a", to: "b", body: "hi", at:, after:, command:))
  end

  it "numbers after what mailbox.md took, and applies one command once" do
    first = send_message(after: 3, command: "c1")
    expect([first["number"], send_message(command: "c1")]).to eq([4, first])
  end

  it "delivers a message whose number is taken under the next free one, and skips one already here" do
    send_message
    arrived = { "id" => "x", "number" => 1, "at" => at.iso8601, "from" => "c", "to" => "d", "body" => "yo", "read" => "yes" }
    expect(section.deliver!(arrived, []).values_at("number", "read")).to eq([2, "no"])
    expect(section.deliver!(arrived, [])).to be_nil
  end

  it "lets only the recipient ack" do
    send_message
    expect { section.ack!(1, "a") }.to raise_error(OpenLanes::Error, /is for b, not a/)
    expect(section.ack!(1, "b")["read"]).to eq("yes")
  end
end
