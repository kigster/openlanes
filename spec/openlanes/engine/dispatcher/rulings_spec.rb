# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Rulings, :tree do
  subject(:rulings) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  let(:driver) { instance_double(OpenLanes::Engine::Verification::Driver, looking: []) }
  let(:result) { OpenLanes::Engine::Verification::Outcome::Result.new(kind: :rejected, to: :rejected, note: "CI failed") }
  let(:settled) { Struct.new(:plan, :result).new("001.00", result) }

  it "does nothing in a run that neither arbitrates nor verifies" do
    expect([rulings.arbitrate, rulings.settle_verifications, desk.wake]).to eq([nil, nil, false])
  end

  it "reopens a plan a look at CI moved, and wakes the run for it" do
    allow(runner).to receive(:verification).and_return(driver)
    allow(driver).to receive(:poll).and_return([settled])
    desk.finished_plans << "001.00"
    rulings.settle_verifications
    expect([desk.finished_plans, desk.wake, desk.verifying]).to eq([[], true, {}])
  end
end
