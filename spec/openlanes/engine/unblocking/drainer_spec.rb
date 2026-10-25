# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Unblocking::Drainer, :tree do
  subject(:drainer) { described_class.new(context, settler:) }

  let(:answered) { "## B1 Rebase\n\nShould I?\n\n## A1\n\nyes\n\nAnswered by dana on 2026-10-13\n" }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:broker) { instance_double(OpenLanes::Agents::Agent, name: "lando-broker", handles?: true) }
  let(:agents) { instance_double(OpenLanes::Agents::Registry, all: [broker]) }
  let(:runner) do
    instance_double(OpenLanes::Engine::Runner, dry_run?: false, blocked: tree.reload.subjects, agents:, claim: true, tree:, executor: nil, events: nil)
  end
  let(:settler) { instance_double(OpenLanes::Engine::Unblocking::Settler, call: nil, forget: nil, failures: { "002.00" => "no" }) }
  let(:unblocker) { instance_double(OpenLanes::Lifecycle::Unblocker, drain: :drained) }
  let(:busy) { [] }
  let(:context) { OpenLanes::Engine::Steps::Context.new(runner:, busy: -> { busy }, wake: -> {}, reopen: ->(_) {}) }

  def drain
    drainer.call
    drainer.each { it.thread.join(2) }
  end

  before do
    plans { |t| t.plan "002.00", :blocked, "rebase", files: { "blocked.md" => answered } }
    allow(OpenLanes::Lifecycle::Unblocker).to receive(:new).and_return(unblocker)
    allow(OpenLanes::UI).to receive(:log)
  end

  it "drains an answered plan on its own thread, through the agent that handles its state" do
    drain

    aggregate_failures do
      expect(drainer.map(&:ordinal)).to eq(["002.00"])
      expect(drainer.first.outcome).to eq(:drained)
      expect(settler).to have_received(:forget).with("002.00")
    end
  end

  it "settles a finished drain on the next tick, and tries an answer set once" do
    drain
    drainer.call

    aggregate_failures do
      expect(settler).to have_received(:call).once
      expect(drainer).to be_empty
      expect(unblocker).to have_received(:drain).once
    end
  end

  it "keeps out of a plan something else is working on" do
    busy << "002.00"
    drain

    expect(drainer).to be_empty
  end

  it "leaves a plan whose questions are not all answered" do
    File.write(File.join(tree.find("002.00").feature.path, "blocked.md"), "## B1 Rebase\n\nShould I?\n")
    drain

    expect(drainer).to be_empty
  end

  it "keeps a drain that raised as its outcome" do
    allow(unblocker).to receive(:drain).and_raise(OpenLanes::Error, "broker died")
    drain

    expect(drainer.first.outcome.message).to eq("broker died")
  end

  it "starts nothing under a dry run, and hands on the settler's failures" do
    allow(runner).to receive(:dry_run?).and_return(true)
    drain

    expect([drainer.to_a, drainer.failures]).to eq([[], { "002.00" => "no" }])
  end
end
