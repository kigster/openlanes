# frozen_string_literal: true

# Decision U3, with the push as a recording lambda: the resolution knows no
# publisher, so none is needed here.
RSpec.describe OpenLanes::Engine::Upkeep::Resolution do
  subject(:resolution) { described_class.new(owed:, push:) }

  let(:owed) { OpenLanes::Engine::Upkeep::Owed.new.tap { it.moved!("main-1", []) } }
  let(:pushes) { [] }
  let(:push) { ->(checkout) { pushes << checkout } }
  let(:conflict) { OpenLanes::Engine::Upkeep::Conflict.new(ordinal: "033.00", number: 1, url: "https://github.com/example/repo/pull/1") }
  let(:checkout) { :checkout }
  let(:done) { instance_double(OpenLanes::Vcs::Refresh::Outcome, done?: true) }

  def result(passed, note = "resolved")
    OpenLanes::Execution::Executor::Result.new(ok: passed, note:, up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
  end

  describe "#rebased" do
    it "pushes a clean rebase once per head of main, and has GitHub asked again" do
      first = resolution.rebased(conflict, checkout, done)
      second = resolution.rebased(conflict, checkout, done)

      aggregate_failures do
        expect([first.ok, first.note]).to eq([true, "PR #1 rebased onto main and pushed"])
        expect(second.note).to include("already pushed against this main")
        expect(pushes).to eq([checkout])
        expect(owed.due.map(&:url)).to eq([conflict.url])
      end
    end

    it "pushes nothing when the rebase did not go through" do
      held = instance_double(OpenLanes::Vcs::Refresh::Outcome, done?: false, reason: "held until main moves")
      report = resolution.rebased(conflict, checkout, held)

      expect([report.ok, report.note, pushes]).to eq([false, "PR #1 not rebased: held until main moves", []])
    end

    it "says a refused push, and leaves it unasked" do
      refusing = described_class.new(owed:, push: ->(_) { raise OpenLanes::Error, "stale info" })
      report = refusing.rebased(conflict, checkout, done)

      expect([report.ok, report.note, owed.due]).to eq([false, "PR #1 rebased but not pushed: stale info", []])
    end
  end

  describe "#finished" do
    it "pushes a resolved conflict" do
      report = resolution.finished(conflict, checkout, result(true), held: nil)

      expect([report.ok, report.note, pushes]).to eq([true, "PR #1 pushed after its rebase onto main; resolved", [checkout]])
    end

    it "asks again for the ladder's next step after an abort, until the ladder is spent (D10)" do
      climbing = resolution.finished(conflict, checkout, result(false, "aborted"), held: nil)
      after_climb = owed.due.size
      owed.settle(owed.due.first)
      resolution.finished(conflict, checkout, result(false, "aborted"), held: "main-1")

      expect([climbing.ok, climbing.note, after_climb, owed.due, pushes]).to eq([nil, "conflicts on PR #1: aborted", 1, [], []])
    end

    it "fails on a crashed job" do
      report = resolution.finished(conflict, checkout, RuntimeError.new("boom"), held: nil)

      expect([report.ok, report.note]).to eq([false, "conflicts on PR #1: boom"])
    end
  end
end
