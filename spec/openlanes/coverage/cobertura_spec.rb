# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Coverage::Cobertura do
  it "prefers lines-covered over lines-valid to the rounded line-rate" do
    expect(described_class.parse(coverage_text("counts.cobertura.xml"))).to eq([1899, 2000])
    expect(OpenLanes::Coverage.read(format: :cobertura, path: coverage_fixture("counts.cobertura.xml")).percent)
      .to eq(94.95)
  end

  it "falls back to line-rate times 100" do
    report = OpenLanes::Coverage.read(format: :cobertura, path: coverage_fixture("rate.cobertura.xml"))
    expect(report.percent).to eq(95.12)
  end

  it "refuses XML without a coverage element" do
    expect { described_class.parse("<report/>") }.to raise_error(OpenLanes::Coverage::Malformed, /<coverage>/)
  end

  it "refuses a coverage element with neither figure" do
    expect { described_class.parse("<coverage branch-rate='1'>") }
      .to raise_error(OpenLanes::Coverage::Malformed, /neither lines-valid nor line-rate/)
  end

  it "refuses a count that is not a whole number" do
    expect { described_class.parse("<coverage lines-covered='x' lines-valid='3'>") }
      .to raise_error(OpenLanes::Coverage::Malformed, /not a line count/)
  end

  it "refuses a line-rate that is not a number, or not a rate" do
    expect { described_class.parse("<coverage line-rate='high'>") }.to raise_error(OpenLanes::Coverage::Malformed, /not a number/)
    expect { described_class.parse("<coverage line-rate='95'>") }.to raise_error(OpenLanes::Coverage::Malformed, /outside 0 to 1/)
  end
end
