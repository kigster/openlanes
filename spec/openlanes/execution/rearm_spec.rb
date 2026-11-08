# frozen_string_literal: true

# An engine down for hours took its agents back on the wall-clock deadline
# the dead engine recorded, so an agent that had barely begun woke at zero.
RSpec.describe OpenLanes::Execution::Rearm do
  subject(:rearm) { described_class.new(deadline:, budget: 3600, seen_at:, started:, tokens:, now:) }

  let(:now) { Time.utc(2026, 11, 6, 12) }
  let(:deadline) { now - (2 * 3600) }
  let(:seen_at) { nil }
  let(:started) { nil }
  let(:tokens) { nil }

  context "with a process younger than ten minutes" do
    let(:started) { now - 120 }

    it("has just started") { expect(rearm.verdict).to eq(:just_started) }
    it("gets its whole budget") { expect(rearm.seconds).to eq(3600) }
  end

  context "with an old process that had spent few tokens" do
    let(:started) { now - (5 * 3600) }
    let(:tokens) { 30_000 }

    it("has just started") { expect(rearm.verdict).to eq(:just_started) }
    it("gets its whole budget") { expect(rearm.seconds).to eq(3600) }
  end

  context "with an old process that had spent many tokens" do
    let(:started) { now - (5 * 3600) }
    let(:tokens) { 900_000 }

    it("has been working") { expect(rearm.verdict).to eq(:working) }
    it("is charged for the hours it ran") { expect(rearm.seconds).to eq(0) }

    context "with time still left on the recorded deadline" do
      let(:deadline) { now + 300 }

      it("keeps it") { expect(rearm.seconds).to eq(300) }
    end
  end

  context "with only the tokens known, and many of them" do
    let(:tokens) { 900_000 }

    it("has been working") { expect(rearm.verdict).to eq(:working) }
  end

  context "with neither reading" do
    it("cannot tell") { expect(rearm.verdict).to eq(:unknown) }
    it("keeps the recorded deadline when no heartbeat says when its engine went") { expect(rearm.seconds).to eq(0) }

    context "with the engine last seen three hours ago" do
      let(:seen_at) { now - (3 * 3600) }

      it("forgives the downtime") { expect(rearm.seconds).to eq(3600) }
    end

    context "with a heartbeat later than now" do
      let(:seen_at) { now + 60 }

      it("forgives nothing") { expect(rearm.seconds).to eq(0) }
    end
  end
end
