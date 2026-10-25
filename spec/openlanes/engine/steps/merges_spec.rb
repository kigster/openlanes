# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Steps::Merges, :tree do
  subject(:merges) { described_class.new(context) }

  let(:merging) { instance_double(OpenLanes::Engine::Merging, assessed?: true, rebase_queued: []) }
  let(:runner) { instance_double(OpenLanes::Engine::Runner, merging:, dry_run?: false, in_scope: subjects) }
  let(:busy) { [] }
  let(:woken) { [] }
  let(:reopened) { [] }
  let(:context) do
    OpenLanes::Engine::Steps::Context.new(runner:, busy: -> { busy }, wake: -> { woken << true }, reopen: ->(o) { reopened << o })
  end
  let(:result) { OpenLanes::Engine::Merging::Result.new(note: "merged PR #1", to: :approved, merged: true) }

  def subjects = OpenLanes::Plans::Tree.new(dir: plans_root).subjects

  before do
    plans { |t| t.plan "033.00", :completed, "merge-risk" }
    allow(merging).to receive(:advance).and_return(result)
    allow(OpenLanes::UI).to receive(:log)
  end

  it "moves an assessed plan on, takes it off the finished plans, and wakes the loop" do
    merges.call

    aggregate_failures do
      expect(OpenLanes::UI).to have_received(:log).with("merged PR #1", plan: "033.00")
      expect([reopened, woken]).to eq([["033.00"], [true]])
    end
  end

  it "passes over a plan something else is working on" do
    busy << "033.00"
    merges.call

    expect(merging).not_to have_received(:advance)
  end

  it "asks GitHub at most once per interval" do
    2.times { merges.call }

    expect(merging).to have_received(:advance).once
  end

  it "logs a note that has not changed, and moves nothing, only once" do
    allow(merging).to receive(:advance).and_return(result.with(to: nil, merged: false))
    allow(OpenLanes::Engine::Steps::Interval).to receive(:new).and_return(instance_double(OpenLanes::Engine::Steps::Interval, due?: true))
    2.times { merges.call }

    expect(OpenLanes::UI).to have_received(:log).with("merged PR #1", plan: "033.00").once
  end

  it "says why a merge was not settled and carries on" do
    allow(merging).to receive(:advance).and_raise(OpenLanes::Error, "gh failed\nmore")
    merges.call

    expect(OpenLanes::UI).to have_received(:log).with("merge not settled: gh failed", level: :warn, plan: "033.00")
  end

  it "does nothing under a dry run" do
    allow(runner).to receive(:dry_run?).and_return(true)
    merges.call

    expect(merging).not_to have_received(:advance)
  end
end
