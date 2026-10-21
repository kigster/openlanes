# frozen_string_literal: true

require_relative "../live/live_context"

# Eight threads tick one dispatcher at once, over one tree, one in-memory bus
# and one fake clock. Whatever interleaving the scheduler picks, no tick may
# raise, and no plan may be handed to an agent twice.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  subject(:stressed) { described_class.new(runner:, clock:) }

  include_context "with a live run"

  let(:threads) { 8 }
  let(:clock) { OpenLanes::Clock::Fake.new(now: Time.now) }
  let(:bus) { OpenLanes::Live::EventBus.for(store) }
  let(:ordinals) { %w[001.00 002.00 003.00 004.00] }

  before do
    srand(38)
    ordinals.each_with_index { |ordinal, i| building(ordinal, "plan-#{i}") }
  end

  after do
    executor.release_all(threads * 2)
    stressed.running.each { it.thread.join(2) }
  end

  # Starts every thread behind one gate, so all of them reach #tick together.
  def tick_together
    gate = Queue.new
    errors = Queue.new
    workers = Array.new(threads) do
      Thread.new do
        gate.pop
        stressed.tick
        bus.publish(keys.news(db: bus.db), JSON.generate(kind: "board"))
        clock.advance(1)
      rescue StandardError => e
        errors << e
      end
    end
    threads.times { gate << :go }
    joined = workers.map { it.join(10) }
    [joined, Array.new(errors.size) { errors.pop }]
  end

  it "runs eight concurrent ticks without raising, losing or duplicating an assignment" do
    joined, errors = tick_together
    # The executor records a call on the agent's own thread, just after start.
    Timeout.timeout(5) { Thread.pass until executor.calls.size >= stressed.running.size + stressed.attempts.size }
    assigned = executor.calls.map { it.split("/").first }
    running = stressed.running.map { it.task.subject.feature.ordinal.to_s }
    aggregate_failures do
      expect(joined).to all(be_a(Thread))
      expect(errors).to eq([])
      expect(assigned).not_to be_empty
      expect(assigned.tally.values).to all(eq(1))
      expect(running.tally.values).to all(eq(1))
      expect(running - ordinals).to eq([])
      expect(clock.monotonic).to eq(threads.to_f)
    end
  end
end
