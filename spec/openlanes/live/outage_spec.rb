# frozen_string_literal: true

require "tmpdir"

# W32: a Redis that stops answering pauses the agents, is asked again on a
# Fibonacci schedule, and either comes back, resuming them, or is given up
# on after the configured hours, shutting the run down.
RSpec.describe OpenLanes::Live::Outage do
  subject(:outage) do
    described_class.new(store:, limit:, clock: -> { time[0] }, wall: -> { Time.at(1_800_000_000 + time[0]) }, **backoff)
  end

  # Jitter off, so the schedule is exact; the jitter has its own examples.
  let(:backoff) { { jitter: false } }

  let(:time) { [0.0] }
  let(:limit) { 3600.0 }
  let(:up) { [true] }
  let(:pings) { [] }
  let(:store) do
    answers = up
    asked = pings
    clock = time
    Object.new.tap do |s|
      s.define_singleton_method(:ping) do
        asked << clock[0]
        answers[0] == :raise ? raise(OpenLanes::Live::Unavailable, "gone") : answers[0]
      end
    end
  end
  let(:dir) { Dir.mktmpdir("outage") }
  let(:state_file) { OpenLanes::Engine::StateFile.new(path: File.join(dir, "openlanes-state.json")) }
  let(:dispatcher) { instance_double(OpenLanes::Engine::Dispatcher, state_file:) }
  let(:control) { OpenLanes::Execution::Control.register(dir, "001.00-luke-backend") }

  before { allow(OpenLanes::UI).to receive(:log) }

  after do
    OpenLanes::Execution::Control.reset!
    FileUtils.rm_rf(dir)
  end

  # Advance the clock to +at+, one tick per second, as the dispatcher would.
  def run_until(at)
    while time[0] < at
      time[0] += 1
      outage.call(dispatcher)
    end
  end

  def saved = JSON.parse(File.read(state_file.path))

  it "rides out a blip shorter than #{described_class::GRACE} seconds" do
    up[0] = false
    run_until(described_class::GRACE - 1)
    up[0] = true
    run_until(30)

    aggregate_failures do
      expect(outage.state).to eq(:up)
      expect(OpenLanes::Execution::Control).not_to be_paused
    end
  end

  context "when Redis stays gone" do
    before do
      control
      up[0] = false
      run_until(described_class::GRACE + 1)
    end

    it "pauses every agent, and records the outage in the state file" do
      aggregate_failures do
        expect(outage).to be_paused
        expect(OpenLanes::Execution::Control).to be_paused
        expect(File.read(control)).to eq("PAUSE\n")
        expect(saved["outage"]).to include("limit_seconds" => 3600, "attempts" => 0)
      end
    end

    it "asks again after 1, 1, 2, 3, 5 seconds" do
      paused_at = time[0]
      pings.clear
      run_until(paused_at + 12)

      expect(pings.map { it - paused_at }).to eq([1, 2, 4, 7, 12])
    end

    it "never waits more than #{described_class::MAX_GAP} seconds between asks" do
      paused_at = time[0]
      pings.clear
      run_until(paused_at + 600)

      gaps = pings.each_cons(2).map { |a, b| b - a }
      aggregate_failures do
        expect(gaps.max).to eq(described_class::MAX_GAP)
        expect(gaps.last(5)).to all(eq(described_class::MAX_GAP))
      end
    end

    context "with redis_backoff settings" do
      let(:backoff) { { initial: 2, cap: 5, jitter: false } }

      it "scales the gaps by the initial delay and caps them" do
        paused_at = time[0]
        pings.clear
        run_until(paused_at + 30)

        expect(pings.map { it - paused_at }).to eq([2, 4, 8, 13, 18, 23, 28])
      end
    end

    context "with full jitter" do
      let(:draws) { [0.5, 0.0, 0.99] }
      let(:backoff) do
        fractions = draws
        { cap: 5, random: Object.new.tap { |r| r.define_singleton_method(:rand) { fractions.shift || 0.5 } } }
      end

      it "draws each gap from below the capped one" do
        paused_at = time[0]
        pings.clear
        run_until(paused_at + 6)

        # 1 * 0.5 at +11.5 is asked on the next tick; then 1 * 0.0, then 2 * 0.99.
        expect(pings.map { it - paused_at }).to eq([1, 2, 4, 6])
      end

      it "never draws a gap above the cap" do
        paused_at = time[0]
        pings.clear
        draws.replace(Array.new(50, 0.999))
        run_until(paused_at + 300)

        expect(pings.each_cons(2).map { |a, b| b - a }.max).to be <= 5
      end
    end

    # Regression: the uncapped schedule asked at ~16.6 and then ~26.8 minutes,
    # so a Redis back at 17 minutes left every agent paused for 10 more.
    it "resumes within #{described_class::MAX_GAP} seconds of Redis coming back after 17 minutes" do
      run_until(17 * 60)
      up[0] = true
      back_at = time[0]
      run_until(back_at + described_class::MAX_GAP)

      aggregate_failures do
        expect(outage.state).to eq(:up)
        expect(OpenLanes::Execution::Control).not_to be_paused
      end
    end

    it "resumes the agents when Redis answers, and files the outage away" do
      run_until(time[0] + 2)
      up[0] = true
      run_until(time[0] + 3)

      aggregate_failures do
        expect(outage.state).to eq(:up)
        expect(OpenLanes::Execution::Control).not_to be_paused
        expect(File.read(control)).to eq("RESUME\n")
        expect(saved).not_to have_key("outage")
        expect(saved["outages"].last).to include("resumed_at", "attempts" => 3)
      end
    end

    # Plan 022: the window {OutageReport} turns into `run.outage`.
    it "hands the ended outage to every on_resume hook" do
      windows = []
      outage.on_resume { windows << it }
      run_until(time[0] + 2)
      up[0] = true
      run_until(time[0] + 3)

      aggregate_failures do
        expect(windows).to eq([outage.window])
        expect(outage.window.seconds.round).to eq(saved["outages"].last["seconds"])
        expect(outage.window.ended_at - outage.window.started_at).to be_within(0.001).of(outage.window.seconds)
      end
    end

    it "shuts the run down once Redis has been gone for the limit" do
      run_until(limit + 1)

      aggregate_failures do
        expect(outage.state).to eq(:gave_up)
        expect(OpenLanes::Execution::Control).to be_quit
        expect(OpenLanes::Execution::Control).not_to be_paused
        expect(saved["outages"].last).to include("gave_up_at")
        expect(OpenLanes::UI).to have_received(:log).with("Redis has not answered for 1 hour: shutting the run down", level: :error)
      end
    end
  end

  it "counts a ping that raises as Redis gone" do
    up[0] = :raise
    run_until(described_class::GRACE + 1)

    expect(outage).to be_paused
  end

  it "says a limit that is not whole hours in hours" do
    paused = described_class.new(store:, limit: 1800.0, clock: -> { time[0] })
    up[0] = false
    (described_class::GRACE + 1).times do
      time[0] += 1
      paused.call(dispatcher)
    end

    expect(OpenLanes::UI).to have_received(:log).with(/giving up after 0.5 hours/, level: :warn)
  end

  it "keeps going when the state file cannot be written" do
    allow(state_file).to receive(:save).and_raise(Errno::EACCES, "read-only")
    up[0] = false
    run_until(described_class::GRACE + 1)

    aggregate_failures do
      expect(outage).to be_paused
      expect(OpenLanes::UI).to have_received(:log).with(/outage not recorded/, level: :warn)
    end
  end
end
