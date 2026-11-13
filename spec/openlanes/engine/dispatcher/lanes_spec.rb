# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Lanes, :tree do
  subject(:lanes) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  it "refuses to discard under --isolation shared, where a reset would wipe the main checkout" do
    expect { lanes.discard("001.00") }.to raise_error(OpenLanes::Error, /this run has none/)
  end

  it "refuses to stop a plan that is not on this run's board" do
    expect { lanes.stop_plan("009.00") }.to raise_error(OpenLanes::Error, /not on this run's board/)
  end

  it "takes a stopped plan out of the run" do
    told = lanes.stop_plan("001.00")
    expect([told, runner.dropped?("001.00")]).to eq([[], true])
  end

  it "fences a plan another machine took: out of the run, and remembered as lost" do
    lanes.fence(%w[001.00 001.00])
    expect([desk.fenced, runner.dropped?("001.00")]).to eq([["001.00"], true])
  end

  it "puts a stopped plan back, with the rounds it used up forgotten" do
    lanes.stop_plan("001.00")
    desk.remember("001.00", coder.name, :building, "Interrupted", 1)
    lanes.restart_plan("001.00")
    expect([runner.dropped?("001.00"), desk.history, desk.wake]).to eq([false, {}, true])
  end

  it "refuses to restart a plan an agent is working" do
    desk.running << job_for(plan, coder)
    expect { lanes.restart_plan("001.00") }.to raise_error(OpenLanes::Error, /already has an agent/)
  end

  it "drops a finished discard on the next tick" do
    desk.discarding["001.00"] = OpenLanes::Engine::Dispatcher::Discard.new(ordinal: "001.00", status: "done")
    lanes.finish_discards
    expect(desk.discarding).to be_empty
  end
end
