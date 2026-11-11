# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Start, :tree do
  subject(:start) { described_class.new(desk, rename:, settle:) }

  include_context "with a dispatcher desk"

  let(:rename) { OpenLanes::Engine::Dispatcher::Rename.new(desk) }
  let(:settle) { instance_double(OpenLanes::Engine::Dispatcher::Settle, end_replacements: nil) }

  # The job runs on a thread of its own and writes its control file under the
  # example's temp directory. Released but not joined, it can still be writing
  # while the directory is removed, which fails the example with ENOTEMPTY.
  after do
    executor.release_all
    desk.running.each { it.thread&.join(5) }
  end

  it "leaves a plan somebody outside openlanes holds exactly as it was" do
    allow(desk.locks).to receive(:reserve).and_raise(OpenLanes::Engine::PlanLocks::Refused, "001.00 is held in alock")
    expect([start.start(coder, plan), desk.refusals.to_a, desk.running]).to eq([nil, ["001.00"], []])
  end

  it "does not start when another run took the plan's lock first" do
    allow(desk.locks).to receive(:hold).and_raise(OpenLanes::Plans::Lock::Held, "locked by another run")
    expect([start.start(coder, plan), desk.running]).to eq([false, []])
  end

  it "puts the job on the desk, with its first round remembered as Started" do
    started = start.start(coder, plan)
    expect([started, desk.running.map(&:key), desk.history[["001.00", coder.name]].map { it[:status] }])
      .to eq([true, ["001.00/#{coder.name}"], ["Started"]])
  end

  # A start that dies after the lock is taken has no thread to release it.
  it "gives the plan's lock back when the checkout cannot be prepared" do
    allow(runner).to receive(:prepare).and_raise(RuntimeError, "no checkout")
    allow(desk.locks).to receive(:release).and_call_original
    expect { start.start(coder, plan) }.to raise_error(RuntimeError, "no checkout")
    expect(desk.locks).to have_received(:release).with("001.00")
  end

  it "starts fresh, and still starts, when state.json cannot be read" do
    allow(OpenLanes::Plans::PlanState).to receive(:for).and_wrap_original do |original, *args|
      original.call(*args).tap { allow(it).to receive(:resumption).and_raise(OpenLanes::Error, "not JSON") }
    end
    expect(start.start(coder, plan)).to be(true)
  end

  describe "#resolve_conflict" do
    let(:upkeep) { instance_double(OpenLanes::Engine::Upkeep::Keeper, later: nil, rebased: report) }
    let(:report) { OpenLanes::Engine::Upkeep::Report.new(ok: true, note: "rebased onto main") }
    let(:conflict) { OpenLanes::Engine::Upkeep::Conflict.new(ordinal: "001.00", number: 7, url: "https://example.test/pull/7") }

    before { allow(desk.locks).to receive(:release).and_call_original }

    it "asks again later about a plan that is no longer in the tree" do
      gone = conflict.with(ordinal: "009.00")
      start.resolve_conflict(upkeep, gone)
      expect(upkeep).to have_received(:later).with(gone)
    end

    it "asks again later when another run holds the plan's lock" do
      allow(desk.locks).to receive(:hold).and_raise(OpenLanes::Plans::Lock::Held, "locked by another run")
      start.resolve_conflict(upkeep, conflict)
      expect(upkeep).to have_received(:later).with(conflict)
    end

    it "gives the lock back when the checkout cannot be prepared" do
      allow(runner).to receive(:prepare).and_raise(RuntimeError, "no checkout")
      expect { start.resolve_conflict(upkeep, conflict) }.to raise_error(RuntimeError, "no checkout")
      expect(desk.locks).to have_received(:release).with("001.00")
    end

    it "hands a clean rebase to the keeper and gives the lock back" do
      start.resolve_conflict(upkeep, conflict)
      expect(upkeep).to have_received(:rebased).with(conflict, nil, nil)
      expect(desk.locks).to have_received(:release).with("001.00")
    end
  end
end
