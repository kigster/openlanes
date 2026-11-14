# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Lanes::Copilot, :tree do
  subject(:copilot) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  it "tells nobody STOP on a plan in scope with no agent, and drops it" do
    expect([copilot.stop_plan("001.00"), runner.dropped?("001.00")]).to eq([[], true])
  end

  it "refuses to restart a plan this node cannot see" do
    expect { copilot.restart_plan("009.00") }.to raise_error(OpenLanes::Error, /not on this node's board/)
  end

  it "refuses to restart a plan another machine has claimed" do
    copilot.stop_plan("001.00")
    allow(runner).to receive(:foreign?).and_return(true)
    expect { copilot.restart_plan("001.00") }.to raise_error(OpenLanes::Error, /not on this node's board/)
  end

  it "takes a restarted plan off the finished list" do
    desk.finished_plans << "001.00"
    copilot.restart_plan("001.00")
    expect(desk.finished_plans).to be_empty
  end
end
