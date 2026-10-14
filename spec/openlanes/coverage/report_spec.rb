# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Coverage::Report do
  let(:dir) { Dir.mktmpdir("coverage-report") }

  after { FileUtils.remove_entry(dir) }

  it "computes the percentage from the counts, never a rounded figure" do
    expect(described_class.new(covered: 18_999, relevant: 20_000).percent).to eq(94.995)
  end

  OpenLanes::Coverage::Config::FORMATS.each do |format|
    context "with #{format}" do
      it "counts a missing report as 0%" do
        report = OpenLanes::Coverage.read(format:, path: File.join(dir, "absent"))
        expect(report).to have_attributes(percent: 0.0, read?: false, problem: /absent is missing/)
      end

      it "counts an unreadable report as 0%" do
        report = OpenLanes::Coverage.read(format:, path: dir)
        expect(report).to have_attributes(percent: 0.0, problem: /cannot be read/)
      end

      it "counts a malformed report as 0%" do
        path = File.join(dir, "garbage")
        File.write(path, "{ this is not a report")
        report = OpenLanes::Coverage.read(format:, path:)
        expect(report).to have_attributes(percent: 0.0, problem: /is not a #{format} report/)
      end
    end
  end

  {
    lcov:      "empty.lcov",
    cobertura: "empty.cobertura.xml",
    istanbul:  "empty-summary.json",
    simplecov: "empty-resultset.json"
  }.each do |format, fixture|
    it "counts an empty #{format} report (nothing instrumented) as 0%" do
      report = OpenLanes::Coverage.read(format:, path: coverage_fixture(fixture))
      expect(report).to have_attributes(percent: 0.0, relevant: 0, problem: /has no instrumented lines/)
    end
  end
end
