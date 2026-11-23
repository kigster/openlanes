# frozen_string_literal: true

require_relative "../../fixtures/plan_state_split/drive"

# Plan 045.04 split PlanState into sections behind a facade. `state.json`
# must come out the same, key order included: the fixture beside the driver
# was recorded by running the same driver against the code before the split.
# Nothing here writes it: a switch that re-recorded it from the code under
# test would compare that code with itself.
RSpec.describe "PlanState after the split", :tree do
  let(:fixture) { File.expand_path("../../fixtures/plan_state_split/state.json", __dir__) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:state) { OpenLanes::Plans::PlanState.for(folder) }

  it "writes state.json byte for byte as the code before the split did" do
    written = "#{JSON.pretty_generate(PlanStateSplitDrive.call(state))}\n"
    expect(written).to eq(File.read(fixture))
  end

  it "loses neither of two writes racing from two threads" do
    agents = %w[one two]
    agents.map { |agent| Thread.new { 10.times { |n| state.sign!(agent:, round: n + 1, status: "Started") } } }.each(&:join)
    expect(state.signatures.map { it["agent"] }.tally).to eq("one" => 10, "two" => 10)
  end
end
