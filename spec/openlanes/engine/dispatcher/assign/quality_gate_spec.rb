# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Assign::QualityGate, :tree do
  subject(:gate) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  it "holds nothing once quality is set" do
    allow(runner).to receive(:awaiting_quality?).and_return(false)
    expect(gate.awaited?).to be(false)
  end

  it "holds dispatch and says so once when nothing is in scope to ask" do
    allow(runner).to receive_messages(awaiting_quality?: true, in_scope: [])
    allow(OpenLanes::UI).to receive(:log)
    2.times { gate.awaited? }
    expect(OpenLanes::UI).to have_received(:log).once
  end
end
