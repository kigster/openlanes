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
end
