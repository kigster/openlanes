# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Assign, :tree do
  subject(:assign) { described_class.new(desk, start:, rescan: 3) }

  include_context "with a dispatcher desk"

  let(:start) { instance_double(OpenLanes::Engine::Dispatcher::Start, start: true) }

  it "offers the building plan to an agent that handles it" do
    agent, subject = assign.next_dispatchable
    expect([agent.handles?(subject.status), subject.feature.ordinal.to_s]).to eq([true, "001.00"])
  end

  it "offers nothing on a plan this run has finished with" do
    desk.finished_plans << "001.00"
    expect(assign.next_dispatchable).to be_nil
  end

  # The backstop behind {OpenLanes::Plans::Tree#husks}: researcher was once
  # sent into a ⚪ New folder with no spec.md.
  it "offers nothing on a plan whose state lacks a file it requires" do
    desk.finished_plans << "001.00"
    plans { |t| t.plan "002.00", :new, "no-spec" }
    expect(assign.next_dispatchable).to be_nil
  end

  it "offers the same plan once the required file is there" do
    desk.finished_plans << "001.00"
    plans { |t| t.plan "002.00", :new, "with-spec", files: { "spec.md" => spec_body } }
    _, picked = assign.next_dispatchable
    expect(picked.feature.ordinal.to_s).to eq("002.00")
  end

  it "starts what it picked, on a pass that begins with no refusals left over" do
    started = []
    desk.refusals << "stale"
    allow(start).to receive(:start) { |_agent, subject| desk.finished_plans << (started << subject.feature.ordinal.to_s).last }
    assign.dispatch
    expect([started, desk.refusals.to_a]).to eq([["001.00"], []])
  end

  # C13: plan 001.00 runs on claude, 002.00 on codex, and an agent is
  # waiting out a rate limit on claude.
  context "when one adapter is paused for a rate limit" do
    let(:adapter) { { "001.00" => "claude", "002.00" => "codex" } }
    let(:started) { [] }

    before do
      building("002.00", "other-cli")
      allow(desk).to receive(:adapter_of) { |_agent, subject| OpenLanes::Adapters.for(adapter.fetch(subject.feature.ordinal.to_s)) }
      allow(start).to receive(:start) { |_agent, subject| desk.finished_plans << (started << subject.feature.ordinal.to_s).last }
      desk.adapter_pause.hold("claude", 120)
    end

    it "starts the plan on the other adapter and not the paused one" do
      assign.dispatch
      expect(started).to eq(["002.00"])
    end

    it "neither fails nor refuses the held plan: it starts once the pause ends" do
      assign.dispatch
      expect([desk.refusals.to_a, desk.past_rounds(plan, coder)]).to eq([[], []])
    end

    it "leaves an agent already running on the paused adapter running" do
      allow(runner).to receive(:jobs).and_return(2)
      running = job_for(plan, coder)
      desk.running << running
      assign.dispatch

      expect([desk.running.include?(running), started]).to eq([true, ["002.00"]])
    end
  end

  it "never rests unless the run stays" do
    desk.idle = true
    expect(assign.resting?).to be(false)
  end

  context "when the run stays and is idle" do
    let(:stay) { true }

    before { desk.idle = true }

    it "rests until the rescan interval has passed" do
      expect(Array.new(4) { assign.resting? }).to eq([true, true, false, true])
    end

    it "looks again at once when woken" do
      desk.wake!
      expect([assign.resting?, desk.wake]).to eq([false, false])
    end
  end
end
