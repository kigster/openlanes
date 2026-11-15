# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::CliPause do
  subject(:pause) { described_class.new(prober:, clock: -> { clock.first }) }

  let(:start) { Time.utc(2026, 11, 13, 8, 0, 0) }
  let(:clock) { [start] }
  let(:now) { start }
  let(:signed_in) { false }
  let(:asked) { [] }
  let(:prober) { ->(name) { (asked << name) && signed_in } }

  before do
    pause.pause("claude", "OAuth session expired")
    clock[0] = now
  end

  it "holds the CLI that failed, and only that one" do
    expect([pause.paused?(:claude), pause.paused?("codex")]).to eq([true, false])
  end

  it "keeps the first reason and time when the same CLI fails again" do
    pause.pause("claude", "not signed in")

    expect(pause.entries.map(&:to_h)).to eq([{ adapter: "claude", reason: "OAuth session expired", since: "2026-11-13T08:00:00Z" }])
  end

  it "names the CLI and why in the idle line" do
    expect(pause.reason).to eq("claude paused: OAuth session expired; waiting for claude auth status")
  end

  it "says nothing in the idle line when nothing is paused" do
    expect(described_class.new(prober:).reason).to be_nil
  end

  context "without the backoff run out" do
    it "does not probe" do
      pause.probe

      expect(asked).to be_empty
    end
  end

  context "when the backoff has run out and the CLI is still signed out" do
    let(:now) { start + described_class::FIRST }

    it "keeps it paused and waits twice as long" do
      pause.probe

      aggregate_failures do
        expect(pause.paused?("claude")).to be(true)
        expect(pause.entries.first.probe_at).to eq(now + (described_class::FIRST * 2))
      end
    end
  end

  context "when a probe passes" do
    let(:now) { start + described_class::FIRST }
    let(:signed_in) { true }

    it "lets the CLI go" do
      aggregate_failures do
        expect(pause.probe).to eq(["claude"])
        expect(pause.paused?("claude")).to be(false)
      end
    end

    it "waits longer when the same CLI fails again soon after, since a probe can pass on an expired token" do
      pause.probe
      pause.pause("claude", "OAuth session expired")

      expect(pause.entries.first.probe_at).to eq(now + (described_class::FIRST * 2))
    end

    it "starts the wait short again once an agent on the CLI has spent something" do
      pause.probe
      pause.clear(:claude)
      pause.pause("claude", "OAuth session expired")

      expect(pause.entries.first.probe_at).to eq(now + described_class::FIRST)
    end
  end
end
