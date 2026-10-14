# frozen_string_literal: true

RSpec.describe OpenLanes::Refusal do
  subject(:refusal) { described_class.new(message: "No plan 999", status: 66) }

  it "carries the message and the exit status" do
    expect([refusal.message, refusal.status]).to eq(["No plan 999", 66])
  end

  it "is a value: equal fields make equal refusals" do
    expect(refusal).to eq(described_class.new(message: "No plan 999", status: 66))
  end
end
