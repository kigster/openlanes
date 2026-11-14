# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::FixedPoint, :tree do
  subject(:fixed_point) { described_class.new(desk, assign) }

  include_context "with a dispatcher desk"

  let(:assign) { instance_double(OpenLanes::Engine::Dispatcher::Assign, next_dispatchable: nil) }

  it "is reached when nothing runs and nothing can start" do
    expect(fixed_point.reached?).to be(true)
  end

  it "is not reached while a job runs" do
    desk.running << job_for(plan, coder)
    expect(fixed_point.reached?).to be(false)
  end

  context "when the run stays" do
    let(:stay) { true }

    it "is never reached on its own" do
      expect(fixed_point.reached?).to be(false)
    end
  end
end
