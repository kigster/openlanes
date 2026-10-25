# frozen_string_literal: true

# The keeper only hands off; one example per duty shows each reaches its owner.
RSpec.describe OpenLanes::Engine::Upkeep::Keeper do
  subject(:keeper) { OpenLanes::Engine::Upkeep.keeper(github:, push: ->(checkout) { pushes << checkout }) }

  let(:github) { instance_double(OpenLanes::Vcs::GitHub, open_pulls_labelled: {}, branch_head: "main-1") }
  let(:pushes) { [] }
  let(:conflict) { OpenLanes::Engine::Upkeep::Conflict.new(ordinal: "033.00", number: 1, url: "https://github.com/example/repo/pull/1") }
  let(:done) { instance_double(OpenLanes::Vcs::Refresh::Outcome, done?: true) }

  it "addresses, sweeps, and puts a conflict it could not start back in the sweep" do
    keeper.later(conflict)

    aggregate_failures do
      expect(keeper.address).to be_empty
      expect(keeper.sweep([]).conflicts).to be_empty
    end
  end

  it "pushes through the push it was built with" do
    keeper.rebased(conflict, :checkout, done)

    expect(pushes).to eq([:checkout])
  end

  it "reaches GitHub through the container when no client is passed" do
    OpenLanes::Container.stub("github", github)
    allow(github).to receive(:open_pulls_labelled).and_return({})

    OpenLanes::Engine::Upkeep.keeper(push: ->(_checkout) {}).address

    expect(github).to have_received(:open_pulls_labelled)
  end
end
