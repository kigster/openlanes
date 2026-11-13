# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Steps::Rename, :tree do
  subject(:renames) { described_class.new(context, discarding:, running: -> { running }) }

  let(:worktree) { instance_double(OpenLanes::Vcs::Worktree, reset: true) }
  let(:runner) { instance_double(OpenLanes::Engine::Runner, tree: OpenLanes::Plans::Tree.new(dir: plans_root), worktree:) }
  let(:reopened) { [] }
  let(:running) { [] }
  let(:discarding) { {} }
  let(:context) do
    OpenLanes::Engine::Steps::Context.new(runner:, busy: -> { [] }, wake: -> {}, reopen: ->(o) { reopened << o })
  end

  def discard(from) = discarding["001.00"] = OpenLanes::Engine::Dispatcher::Discard.new(ordinal: "001.00", from:)

  before do
    plans { |t| t.plan "001.00", :building, "tic-tac-toe" }
    allow(OpenLanes::UI).to receive(:log)
  end

  it "throws a discard back once its agents are gone, resetting the worktree and reopening the plan" do
    entry = discard(:building)
    renames.call

    aggregate_failures do
      expect(worktree).to have_received(:reset)
      expect([entry.status, entry.reason]).to eq(["done", "001.00 reset, and stays at 🟡 Building, where its work started"])
      expect(reopened).to eq(["001.00"])
    end
  end

  it "waits while an agent is still running on the plan" do
    entry = discard(:building)
    running << "001.00"
    renames.call

    aggregate_failures do
      expect(entry.status).to be_nil
      expect(worktree).not_to have_received(:reset)
    end
  end

  it "drops a finished discard on the next tick" do
    discard(:building)
    2.times { renames.call }

    expect(discarding).to be_empty
  end

  it "refuses a discard whose folder vanished" do
    discarding["009.00"] = OpenLanes::Engine::Dispatcher::Discard.new(ordinal: "009.00", from: nil)
    renames.call

    expect(discarding["009.00"].to_a.values_at(1, 2)).to eq(["refused", "009.00's folder vanished"])
  end

  it "refuses, with the machine's reason, a state the plan cannot go back to" do
    entry = discard(:new)
    renames.call

    aggregate_failures do
      expect(entry.status).to eq("refused")
      expect(entry.reason).to start_with("001.00's agents were stopped, but:")
      expect(reopened).to be_empty
    end
  end

  describe ".started_from" do
    it "picks the earliest start, the one with the longest road ahead" do
      jobs = [Struct.new(:from).new(:building), Struct.new(:from).new(:planned), Struct.new(:from).new(nil)]

      expect(described_class.started_from(jobs)).to eq(:planned)
    end

    it "is nil when no agent was running" do
      expect(described_class.started_from([])).to be_nil
    end
  end
end
