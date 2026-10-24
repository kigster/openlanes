# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Verification::Report do
  it "reads the verdict and the failing step, as chewie-verifier.md asks for them" do
    report = described_class.parse(<<~MARKDOWN)
      # Verification, round 1

      Verdict: rejected

      ## Steps

      1. Open the board: passed
      2. Click New game: failed (step-02.png)

      ## Failing step

      - Step: 2
      - What: Click "New game"
      - Expected: a 9 by 9 grid appears
      - Seen: the page says "500 Internal Server Error"

      ## Notes

      - Seen: not this one
    MARKDOWN

    expect(report).to have_attributes(verdict: :rejected,
      step: 2,
      what: 'Click "New game"',
      expected: "a 9 by 9 grid appears",
      seen: 'the page says "500 Internal Server Error"',
      screenshot: "step-02.png")
  end

  it "takes bold keys and a verified verdict" do
    report = described_class.parse("**Verdict:** verified\n\n## Failing step\n\n**Step:** 3\n")

    expect([report.verdict, report.step]).to eq([:verified, 3])
  end

  it "leaves out what the report does not say" do
    expect(described_class.parse("# nothing here\n")).to have_attributes(verdict: nil, step: nil, screenshot: nil)
  end

  # Plan 035: an mvp skip must not read as chewie having verified the PR.
  it "reads a skipped (mvp) verdict as skipped, never verified" do
    report = described_class.parse("# Verification, round 1\n\nVerdict: skipped (mvp)\n\nSkipped: chewie did not run.\n")

    expect(report.verdict).to eq(:skipped)
  end
end
