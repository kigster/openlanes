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

  it "finishes: review-in-progress comes off a pull request nobody is reviewing" do
    allow(github).to receive(:pulls_labelled).and_return(7 => %w[review-in-progress])
    allow(github).to receive(:remove_label)

    aggregate_failures do
      expect(keeper.finish([])).to eq(["PR #7: review-in-progress taken off, nobody is reviewing it"])
      expect(github).to have_received(:remove_label).with(number: 7, name: "review-in-progress")
    end
  end

  it "finishes nothing when built without that duty" do
    bare = described_class.new(addressing: nil, sweep: nil, resolution: nil, owed: nil)

    expect(bare.finish([])).to be_empty
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
