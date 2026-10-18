# frozen_string_literal: true

require "tmpdir"

# W32: a Redis that stops answering pauses the agents, is asked again on a
# Fibonacci schedule, and either comes back, resuming them, or is given up
# on after the configured hours, shutting the run down.
RSpec.describe OpenLanes::Live::Outage do
  subject(:outage) { described_class.new(store:, limit:, clock: -> { time[0] }, wall: -> { Time.at(1_800_000_000 + time[0]) }) }

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
