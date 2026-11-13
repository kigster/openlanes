# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Rename, :tree do
  subject(:rename) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  def folder = File.basename(tree.reload.subjects.first.feature.path)

  it "leaves the folder alone when the agent starts in the state it was picked at" do
    stays = instance_double(OpenLanes::Agents::Agent, starts_as: nil)
    expect(rename.rename_on_start(plan, stays)).to equal(plan)
  end

  it "keeps a pair's hold while a partner still runs on the plan" do
    desk.holds["001.00"] = :ready_for_review
    desk.running << job_for(plan, coder)
    rename.apply_hold("001.00")
    expect(desk.holds).to eq("001.00" => :ready_for_review)
  end

  it "drops a hold, renaming nothing, once the plan is being discarded" do
    before = folder
    desk.holds["001.00"] = :ready_for_review
    desk.discarding["001.00"] = OpenLanes::Engine::Dispatcher::Discard.new(ordinal: "001.00")
    rename.apply_hold("001.00")
    expect([desk.holds, folder]).to eq([{}, before])
  end

  it "reports a Blocked signature the folder does not justify, and leaves it where it was" do
    before = folder
    entry = OpenLanes::Plans::Ledger::Entry.new(at: Time.now, agent: coder.name, status: "Blocked", round: 1, file: "plan.md", line: 1)
    base = OpenLanes::Engine::Runner::Attempt.new(ordinal: "001.00",
      agent: coder.name,
      from: :building,
      to: :building,
      ok: true,
      note: "",
      up: 0,
      down: 0,
      subagents: 0,
      delegated: 0,
      seconds: 0)
    parked = rename.park(job_for(plan, coder), base, entry)
    expect([parked.ok, parked.status, folder]).to eq([false, "Blocked", before])
  end
end
