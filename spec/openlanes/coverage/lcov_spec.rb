# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Coverage::Lcov do
  it "sums LH and LF over every file rather than averaging per-file percentages" do
    expect(described_class.parse(coverage_text("two-files.lcov"))).to eq([1000, 1010])
    expect(OpenLanes::Coverage.read(format: :lcov, path: coverage_fixture("two-files.lcov")).percent)
      .to be_within(0.001).of(99.0099)
  end

  it "counts DA lines in a record that carries no LF/LH" do
    expect(described_class.parse(coverage_text("da-only.lcov"))).to eq([2, 4])
  end

  it "reads an empty file as nothing instrumented" do
    expect(described_class.parse("")).to eq([0, 0])
  end

  it "refuses text with no SF record" do
    expect { described_class.parse("<html>not lcov</html>") }.to raise_error(OpenLanes::Coverage::Malformed, /SF/)
  end
end
