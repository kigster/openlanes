# frozen_string_literal: true

# C13: a rate limit on one agent pauses new starts on its adapter until the
# wait ends. The clock is a fake one, so nothing here waits.
RSpec.describe OpenLanes::Execution::Throttle::AdapterPause do
  subject(:pause) { described_class.new(clock: -> { clock.now }) }

  let(:start) { Time.utc(2026, 11, 20, 9, 40) }
  let(:clock) { OpenLanes::Clock::Fake.new(now: start) }

  def advance(seconds) = clock.advance(seconds)

  it "pauses nothing to begin with" do
    expect([pause.paused?("claude"), pause.entries, pause.reason]).to eq([false, [], nil])
  end

  it "pauses the adapter for the wait, and only that adapter" do
    pause.hold("claude", 120)

    expect([pause.paused?("claude"), pause.paused?(:claude), pause.paused?("codex")]).to eq([true, true, false])
  end

  it "says which adapter is paused, for what, and until when" do
    pause.hold("claude", 120)

    expect(pause.reason).to eq("claude paused for rate limit until #{(start + 120).strftime("%H:%M")}")
  end

  it "lifts by the clock alone when the wait ends" do
    pause.hold("claude", 120)
    advance(120)

    expect([pause.paused?("claude"), pause.entries]).to eq([false, []])
  end

  it "is extended by a later, longer wait, keeping when it began" do
    pause.hold("claude", 60)
    advance(30)
    pause.hold("claude", 300, cause: "provider overload")

    expect(pause["claude"].to_h)
      .to eq(adapter: "claude", reason: "paused for provider overload", since: start.iso8601, until: (start + 330).iso8601)
  end

  it "is not cut short by a later, shorter wait" do
    pause.hold("claude", 600)
    pause.hold("claude", 30)
    advance(31)

    expect(pause["claude"].ends_at).to eq(start + 600)
  end

  it "starts afresh once a pause has run out" do
    pause.hold("claude", 60)
    advance(90)
    pause.hold("claude", 60)

    expect(pause["claude"].since).to eq(start + 90)
  end

  it "lists the pauses still running, oldest first" do
    pause.hold("codex", 30)
    advance(1)
    pause.hold("claude", 600)
    advance(1)
    pause.hold("gemini", 600)
    advance(30)

    expect(pause.entries.map(&:adapter)).to eq(%w[claude gemini])
  end
end
