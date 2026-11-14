# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Restart, :tree do
  subject(:restart) { described_class.new(desk, options, start: nil) }

  include_context "with a dispatcher desk"

  let(:options) { OpenLanes::Engine::Dispatcher::Options.with_defaults(runner:, clock: OpenLanes::Clock::System, converter: nil) }

  it "takes nothing back and writes no heartbeat when there is no state file" do
    expect([restart.reattach, restart.persist]).to eq([[], nil])
  end

  it "builds the question conversions over the desk's runner" do
    expect(restart.conversions).to be_a(OpenLanes::Engine::Conversions)
  end
end
