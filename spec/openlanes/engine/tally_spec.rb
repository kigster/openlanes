# frozen_string_literal: true

require "spec_helper"

# The loop reports which plan moved and which agent failed. This is the part
# nobody could see afterwards: what the run cost to get there.
RSpec.describe OpenLanes::Engine::Tally do
  subject(:tally) { described_class.new(attempts:, seconds: 600.0) }

  def attempt(agent, ordinal, up:, down:, seconds:, subagents: 0, delegated: 0)
    OpenLanes::Engine::Runner::Attempt.new(ordinal:,
      agent:,
      from: :planned,
      to: :building,
      ok: true,
      note: "completed",
      up:,
      down:,
      subagents:,
      delegated:,
      seconds:)
  end

  let(:attempts) do
    [
      attempt("luke-backend", "003.00", up: 1_200_000, down: 18_400, seconds: 300.0),
      attempt("luke-backend",
        "004.00",
        up:        800_000,
        down:      12_000,
        seconds:   240.0,
        subagents: 3,
        delegated: 68_000),
      attempt("hansolo-reviewer", "003.00", up: 300_000, down: 4_000, seconds: 90.0)
    ]
  end

  describe "what it counts" do
    it "counts a plan once however many agents ran against it" do
      expect(tally.plans).to eq(2)
    end

    it "adds up both directions across every agent" do
      aggregate_failures do
        expect(tally.up).to eq(2_300_000)
        expect(tally.down).to eq(34_400)
      end
    end

    # Agent-seconds over wall-clock seconds. Below the `-j` ceiling by however
    # much each round spent waiting for its slowest member.
    it "reports how many agents were running at any given moment" do
      expect(tally.concurrency).to be_within(0.01).of(1.05)
    end

    it "leaves the concurrency at zero rather than dividing by it" do
      expect(described_class.new(attempts:, seconds: 0.0).concurrency).to be_zero
    end

    # A round that fell over before any agent started has no ordinal to
    # attribute anything to, and used to be counted as a plan.
    it "ignores an attempt that never reached a plan" do
      broken = OpenLanes::Engine::Runner::Attempt.new(ordinal: "?",
        agent: "?",
        from: :unknown,
        to: :unknown,
        ok: false,
        note: "boom",
        up: 0,
        down: 0,
        subagents: 0,
        delegated: 0,
        seconds: 0.0)

      expect(described_class.new(attempts: attempts + [broken], seconds: 600.0).plans).to eq(2)
    end
  end

  describe "#by_agent" do
    it "gives one row per agent, dearest first" do
      expect(tally.by_agent.map(&:name)).to eq(%w[luke-backend hansolo-reviewer])
    end

    it "adds an agent's rounds together rather than reporting the last one" do
      expect(tally.by_agent.first).to have_attributes(invocations: 2, subagents: 3, up: 2_000_000, down: 30_400)
    end
  end

  describe "#render" do
    it "names every agent, its sub-agents and what it spent" do
      expect(tally.render).to match(/luke-backend +2 +3 +2\.0M +30k/)
    end

    # Sub-agent spend arrives as one number with no split between the
    # directions, so saying how much of the total that was is the only honest
    # way to report it as ↑.
    it "says how much of the total arrived unsplit" do
      expect(tally.render).to include("68k").and include("counted above as ↑")
    end

    it "says nothing about sub-agents where none ran" do
      quiet = described_class.new(attempts: [attempts.first], seconds: 300.0)

      expect(quiet.render).not_to include("counted above as ↑")
    end

    it "still reports the run when no agent was started" do
      expect(described_class.new(attempts: [], seconds: 12.0).render)
        .to include("0 plans addressed").and include("0 invocations").and include("12s")
    end

    # The loop has no rounds of its own: each agent counts its own per plan,
    # so the summary counts what was actually started.
    it "counts invocations rather than rounds" do
      expect(tally.summary).to include("3 invocations")
    end

    it "reads the clock in minutes and hours rather than in four-figure seconds" do
      expect(described_class.new(attempts: [], seconds: 3900.0).render).to include("1h05m")
    end
  end
end
