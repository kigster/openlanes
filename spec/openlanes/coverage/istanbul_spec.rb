# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Coverage::Istanbul do
  it "reads total.lines, not statements" do
    expect(described_class.parse(coverage_text("coverage-summary.json"))).to eq([3800, 4000])
  end

  it "reads a blank summary (pct Unknown, total 0) as nothing instrumented" do
    expect(described_class.parse(coverage_text("empty-summary.json"))).to eq([0, 0])
  end

  it "refuses JSON without total.lines" do
    expect { described_class.parse('{"total": {}}') }.to raise_error(OpenLanes::Coverage::Malformed, /total.lines/)
    expect { described_class.parse("[]") }.to raise_error(OpenLanes::Coverage::Malformed, /total.lines/)
  end

  it "refuses counts that are not whole numbers" do
    expect { described_class.parse('{"total": {"lines": {"covered": "9", "total": 10}}}') }
      .to raise_error(OpenLanes::Coverage::Malformed, /whole-number/)
  end
end
