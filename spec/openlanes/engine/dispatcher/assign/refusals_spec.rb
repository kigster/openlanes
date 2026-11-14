# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Assign::Refusals, :tree do
  subject(:refusals) { described_class.new(desk).tap(&:prepare) }

  include_context "with a dispatcher desk"

  it "refuses nothing about a free plan" do
    expect(refusals.refused?(plan)).to be(false)
  end

  it "refuses a plan being discarded" do
    desk.discarding["001.00"] = OpenLanes::Engine::Dispatcher::Discard.new(ordinal: "001.00")
    expect(refusals.refused?(plan)).to be(true)
  end

  it "refuses a plan this pass could not claim" do
    desk.refusals << "001.00"
    expect(refusals.refused?(plan)).to be(true)
  end

  it "refuses a plan over its budget" do
    allow(desk).to receive(:budget_refusal).and_return("over budget: $6.00 of $5.00")
    allow(OpenLanes::UI).to receive(:log)
    expect(refusals.refused?(plan)).to be(true)
  end
end
