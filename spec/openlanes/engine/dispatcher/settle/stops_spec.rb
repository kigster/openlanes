# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Settle::Stops, :tree do
  subject(:stops) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  it "names no stop for a plan the harness left alone" do
    expect(stops.stopped_for("001.00")).to be_nil
  end

  it "names a fenced plan's stop before a discarded one's" do
    desk.fenced << "001.00"
    desk.discarding["001.00"] = OpenLanes::Engine::Dispatcher::Discard.new(ordinal: "001.00")
    expect(stops.stopped_for("001.00")).to eq("claim lost to another machine")
  end

  it "says how many rounds an agent has left" do
    entry = OpenLanes::Plans::Ledger::Entry.new(at: Time.now, agent: coder.name, status: "Almost completed", round: 1, file: "", line: 0)
    expect(stops.retry_note(coder, entry)).to start_with("Almost completed; ")
  end
end
