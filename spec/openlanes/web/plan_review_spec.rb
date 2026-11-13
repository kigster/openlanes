# frozen_string_literal: true

RSpec.describe OpenLanes::Web::PlanReview, :tree do
  subject(:review) { described_class.new(plans_dir: plans_root, diff:) }

  let(:diff) { ->(feature) { { stat: feature.slug, patch: "", truncated: false } } }

  before do
    plans do |t|
      t.plan("003.00",
        :ready_for_review,
        "tax-rule-dsl",
        files: { "pull-requests.md" => "## Findings: staff-reviewer\n\n### F1 [critical] lib/tax.rb:9\n\nRounds.\n" })
    end
  end

  it "answers the plan's diff and findings" do
    expect(review.call("3")).to eq(diff: { stat: "tax-rule-dsl", patch: "", truncated: false },
      findings: [{ id: "F1", reviewer: "staff-reviewer", severity: "critical", file: "lib/tax.rb", line: 9, text: "Rounds.", ruling: nil }])
  end

  it "shows a person's strike once it is recorded" do
    path = OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first.feature.path
    OpenLanes::Live::Commands.rule!(path, OpenLanes::Plans::Findings.for(path).first, "strike", by: "kig")
    expect(review.call("003.00")[:findings].map { it[:ruling] }).to eq(["strike"])
  end

  it "refuses a number that is no plan, and a plan that is not there" do
    aggregate_failures do
      expect { review.call("x") }.to raise_error(described_class::NotFound, "x is not a plan number")
      expect { review.call("7") }.to raise_error(described_class::NotFound, "there is no plan 007.00")
    end
  end
end
