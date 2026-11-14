# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Assign::IdleReason, :tree do
  subject(:reason) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  # The drain of answered blocks: none under way, with the failures given.
  def drainer(failures = {}) = Struct.new(:failures) { def map(&) = [] }.new(failures)

  before { desk.unblocking = drainer }

  it "says nothing to do when a plan in scope waits on nothing" do
    expect(reason.call([plan])).to eq("idle: nothing to do")
  end

  it "names the plans waiting for answers" do
    allow(desk).to receive(:waiting).and_return(["002.00"])
    desk.unblocking = drainer
    expect(reason.call([plan])).to eq("idle: waiting for answers on 002.00")
  end

  it "names a failed unblock with its reason" do
    allow(desk).to receive(:waiting).and_return(["002.00"])
    desk.unblocking = drainer({ "002.00" => "boom" })
    expect(reason.call([plan])).to include("unblock failed on 002.00 (boom)")
  end
end
