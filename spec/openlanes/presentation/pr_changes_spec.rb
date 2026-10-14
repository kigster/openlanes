# frozen_string_literal: true

RSpec.describe OpenLanes::Presentation::PrChanges do
  subject(:presenter) { described_class.new(changes, dry_run:) }

  let(:dry_run) { false }

  def change(number, new_title, reason: "branch", ambiguous: false, assumed: false, adopted: false, ordinal: nil)
    OpenLanes::Lifecycle::Resync::Prs::Change.new(number:, title: "Title #{number}", new_title:, ordinal:,
      reason:, ambiguous:, assumed:, adopted:)
  end

  def report
    err = CapturedStream.new
    original, $stderr = $stderr, err
    presenter.report
    strip_ansi(err.string)
  ensure
    $stderr = original
  end

  describe "#lines" do
    let(:changes) { [change(1, "[001.00] One"), change(2, nil, reason: "two plans claim it", ambiguous: true)] }

    it "is one tab-separated row per change, with a dash for no new title" do
      expect(presenter.lines).to eq(["1\t[001.00] One\tbranch", "2\t-\ttwo plans claim it"])
    end
  end

  describe "#report" do
    let(:changes) do
      [
        change(1, "[001.00] One"),
        change(2, "[dev] Two", assumed: true),
        change(3, "[004.00] Three", adopted: true, ordinal: OpenLanes::Plans::Ordinal.parse("004.00")),
        change(4, nil, reason: "two plans claim it", ambiguous: true)
      ]
    end

    it "lists retitles with their notes, adoptions, skips, the total and the assumption warning" do
      expect(report).to include(
        "#1  [001.00] One",
        "#2  [dev] Two   (assumed)",
        "#3  [004.00] Three   (new plan)",
        "Created 1 plan folder for pull requests that resolved to no plan",
        "004.00  #3  Title 3",
        "#4  SKIPPED — two plans claim it",
        "Retitled 3 pull requests.",
        "1 title would get [#{OpenLanes::NO_PLAN_PREFIX}] because no plan resolved."
      )
    end

    context "on a dry run" do
      let(:dry_run) { true }

      it "says it would, and that nothing changed" do
        expect(report).to include("Would create 1 plan folder", "3 retitles pending — nothing was changed.")
      end
    end

    context "on a dry run where nothing applies" do
      let(:dry_run) { true }
      let(:changes) { [change(4, nil, reason: "two plans claim it", ambiguous: true)] }

      it "draws no pending footer" do
        expect(report).not_to include("pending")
      end
    end
  end
end
