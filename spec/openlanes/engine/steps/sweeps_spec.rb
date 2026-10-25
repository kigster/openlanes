# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Steps::Sweeps do
  subject(:sweeps) { described_class.new(context, resolve: ->(keeper, conflict) { resolved << [keeper, conflict] }) }

  let(:conflict) { OpenLanes::Engine::Upkeep::Conflict.new(ordinal: "033.00", number: 1, url: "https://github.com/example/repo/pull/1") }
  let(:sweep) { OpenLanes::Engine::Upkeep::Sweep::Result.new(notes: ["PR #1 behind"], conflicts: [conflict]) }
  let(:upkeep) { instance_double(OpenLanes::Engine::Upkeep::Keeper, address: ["PR #2 addressed"], sweep:) }
  let(:runner) { instance_double(OpenLanes::Engine::Runner, upkeep:, dry_run?: false, in_scope: []) }
  let(:resolved) { [] }
  let(:context) { OpenLanes::Engine::Steps::Context.new(runner:, busy: -> { ["001.00"] }, wake: -> {}, reopen: ->(_) {}) }

  before { allow(OpenLanes::UI).to receive(:log) }

  it "logs what it addressed and swept, and hands every conflict to the dispatcher" do
    sweeps.call

    aggregate_failures do
      expect(upkeep).to have_received(:sweep).with([], busy: ["001.00"])
      expect(OpenLanes::UI).to have_received(:log).with("PR #2 addressed")
      expect(OpenLanes::UI).to have_received(:log).with("PR #1 behind")
      expect(resolved).to eq([[upkeep, conflict]])
    end
  end

  it "asks GitHub at most once per interval" do
    2.times { sweeps.call }

    expect(upkeep).to have_received(:address).once
  end

  it "says GitHub could not be asked, and carries on" do
    allow(upkeep).to receive(:address).and_raise(OpenLanes::Error, "rate limited")
    sweeps.call

    expect(OpenLanes::UI).to have_received(:log).with("pull requests not kept up this time: rate limited", level: :warn)
  end

  it "keeps nothing without a keeper" do
    allow(runner).to receive(:upkeep).and_return(nil)

    expect(sweeps.call).to be_nil
  end
end
