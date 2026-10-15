# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Coverage::Simplecov do
  it "merges every command's runs line by line, then counts covered over relevant" do
    merged = described_class.lines_by_file(coverage_text("resultset.json"))

    expect(merged).to eq("/repo/lib/a.rb" => [1, 2, nil, 0, 5],
      "/repo/lib/b.rb" => [nil, 0, 0],
      "/repo/lib/c.rb" => [1, nil, 1, 0])
    expect(described_class.parse(coverage_text("resultset.json"))).to eq([5, 9])
  end

  it "matches SimpleCov's covered / (covered + missed)" do
    covered, missed = 5, 4
    report = OpenLanes::Coverage.read(format: :simplecov, path: coverage_fixture("resultset.json"))
    expect(report.percent).to eq(100.0 * covered / (covered + missed))
  end

  it "treats a count that is not an integer as not code" do
    text = '{"RSpec": {"coverage": {"a.rb": {"lines": ["ignored", 1, 0]}}}}'
    expect(described_class.parse(text)).to eq([1, 2])
  end

  it "refuses a resultset of the wrong shape" do
    expect { described_class.parse("[]") }.to raise_error(OpenLanes::Coverage::Malformed, /mapping/)
    expect { described_class.parse('{"RSpec": {}}') }.to raise_error(OpenLanes::Coverage::Malformed, /RSpec has no coverage/)
    expect { described_class.parse('{"RSpec": {"coverage": {"a.rb": {}}}}') }
      .to raise_error(OpenLanes::Coverage::Malformed, /a.rb has no line counts/)
  end
end
