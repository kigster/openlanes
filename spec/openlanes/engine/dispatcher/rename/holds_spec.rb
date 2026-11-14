# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Rename::Holds, :tree do
  subject(:holds) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  let(:attempt) { OpenLanes::Engine::Runner::Attempt.new(**OpenLanes::Engine::Runner::Attempt.members.to_h { [it, nil] }, note: "done") }

  it "records the hold and says it waits for the partner" do
    held = holds.hold("001.00", :building_ui, attempt)
    expect([desk.holds, held.note]).to match([{ "001.00" => :building_ui }, start_with("done; holds at")])
  end

  it "keeps the hold while an agent of the plan still runs" do
    desk.holds["001.00"] = :building_ui
    desk.running << job_for(plan, coder)
    holds.apply_hold("001.00")
    expect(desk.holds).to eq("001.00" => :building_ui)
  end

  it "drops the hold on a discarded plan without renaming it" do
    desk.holds["001.00"] = :building_ui
    desk.discarding["001.00"] = OpenLanes::Engine::Dispatcher::Discard.new(ordinal: "001.00")
    holds.apply_hold("001.00")
    expect([desk.holds, tree.reload.subjects.first.status.key]).to eq([{}, :building])
  end
end
