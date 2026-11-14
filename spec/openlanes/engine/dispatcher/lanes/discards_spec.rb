# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Lanes::Discards, :tree do
  subject(:discards) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  it "refuses a discard in a run with no worktree of its own" do
    expect { discards.check!("001.00", []) }.to raise_error(OpenLanes::Error, /this run has none/)
  end

  it "refuses a discard of a plan that is not there" do
    allow(runner).to receive_messages(isolated?: true, dry_run?: false)
    expect { discards.check!("009.00", []) }.to raise_error(OpenLanes::Error, /there is no plan 009.00/)
  end

  it "leaves a discard whose agents are still running for a later tick" do
    desk.running << job_for(plan, coder)
    desk.discarding["001.00"] = OpenLanes::Engine::Dispatcher::Discard.new(ordinal: "001.00")
    discards.complete
    expect(desk.discarding["001.00"].status).to be_nil
  end

  it "reports a discard whose folder vanished as refused" do
    allow(desk).to receive(:fresh_by).and_return(nil)
    desk.discarding["001.00"] = OpenLanes::Engine::Dispatcher::Discard.new(ordinal: "001.00")
    discards.complete
    expect(desk.discarding["001.00"].then { [it.status, it.reason] }).to eq(["refused", "001.00's folder vanished"])
  end
end
