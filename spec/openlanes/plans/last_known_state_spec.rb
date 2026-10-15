# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::LastKnownState do
  def agent(round) = described_class.new(source: "agent", round:, status: "Interrupted", done: ["B1"])

  def harness(round) = described_class.new(source: "harness", round:, status: "Interrupted", note: "harness died")

  describe "#supersedes?" do
    it "lets anything replace nothing" do
      expect([agent(1).supersedes?(nil), harness(1).supersedes?(nil)]).to eq([true, true])
    end

    it "lets an agent entry replace anything, in any round" do
      expect([agent(1).supersedes?(harness(3)), agent(1).supersedes?(agent(2))]).to eq([true, true])
    end

    it "never lets the harness replace an agent entry of the same round or a later one" do
      expect([harness(1).supersedes?(agent(1)), harness(1).supersedes?(agent(2))]).to eq([false, false])
    end

    it "lets the harness replace an agent entry from an earlier round, and its own" do
      expect([harness(2).supersedes?(agent(1)), harness(2).supersedes?(harness(1))]).to eq([true, true])
    end
  end

  it "refuses a source or status outside the vocabulary" do
    aggregate_failures do
      expect { described_class.new(source: "robot", round: 1, status: "Interrupted") }
        .to raise_error(OpenLanes::Error, /source/)
      expect { described_class.new(source: "agent", round: 1, status: "Sleeping") }
        .to raise_error(OpenLanes::Error, /status/)
    end
  end

  it "round-trips through the JSON shape, leaving empty fields out" do
    entry = agent(2)
    json = entry.to_json_h

    aggregate_failures do
      expect(json.keys).to contain_exactly("source", "at", "round", "status", "done")
      expect(described_class.from_h(json)).to eq(entry)
    end
  end

  it "writes a Time as ISO 8601" do
    at = Time.new(2026, 9, 17, 13, 37, 4, "-07:00")
    expect(described_class.new(source: "agent", round: 1, status: "Interrupted", at:).at).to eq("2026-09-17T13:37:04-07:00")
  end
end
