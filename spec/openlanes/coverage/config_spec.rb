# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Coverage::Config do
  let(:root) { Dir.mktmpdir("coverage-config") }
  let(:path) { File.join(root, ".openlanes.yml") }
  let(:reported) do
    { "command" => "bundle exec rspec", "report" => "coverage/.resultset.json", "format" => "simplecov", "minimum" => 95 }
  end
  let(:printed) do
    { "command" => "bundle exec rspec", "report_command" => "jq '.total.lines.percent' coverage/coverage.json", "minimum" => 95 }
  end

  after { FileUtils.remove_entry(root) }

  def write(coverage, **others)
    File.write(path, coverage.is_a?(String) ? coverage : YAML.dump(others.transform_keys(&:to_s).merge("coverage" => coverage)))
  end

  def expect_invalid(coverage, message)
    write(coverage)
    expect { described_class.load(root) }.to raise_error(OpenLanes::Coverage::Invalid, /\A#{Regexp.escape(path)}: coverage#{message}/)
  end

  it "reads a report with its format" do
    write(reported)
    config = OpenLanes::Coverage.config(root)

    expect(config).to have_attributes(path:,
      command: "bundle exec rspec",
      report: "coverage/.resultset.json",
      format: :simplecov,
      report_command: nil,
      minimum: 95.0,
      report_command?: false,
      source: "simplecov: coverage/.resultset.json")
    expect(config.report_path(root)).to eq(File.join(root, "coverage/.resultset.json"))
  end

  it "reads a report_command, with no report and no format" do
    write(printed)
    config = described_class.load(root)

    expect(config).to have_attributes(report_command: "jq '.total.lines.percent' coverage/coverage.json",
      report: nil,
      format: nil,
      report_command?: true,
      source: "report_command: `jq '.total.lines.percent' coverage/coverage.json`")
    expect(config.report_path(root)).to be_nil
  end

  it "sits beside the file's other sections, which still apply" do
    write(printed, jobs: 3)

    expect(OpenLanes::Config.load(root)).to have_attributes(jobs: 3, coverage: described_class.load(root))
  end

  it "survives Config#to_yaml" do
    write(reported, jobs: 3)
    again = OpenLanes::Config.parse(OpenLanes::Config.load(root).to_yaml, path:)

    expect(again.coverage).to eq(described_class.load(root))
  end

  it "accepts a fractional minimum and the bounds" do
    [0, 100, 94.5].each do |minimum|
      write(reported.merge("minimum" => minimum))
      expect(described_class.load(root).minimum).to eq(minimum.to_f)
    end
  end

  it "is nil when the file has no coverage: section" do
    File.write(path, "jobs: 2\n")

    expect(described_class.load(root)).to be_nil
  end

  it "is nil when there is no .openlanes.yml" do
    expect(described_class.load(root)).to be_nil
  end

  it "reads nothing from the retired .openlanes.coverage.yml" do
    File.write(File.join(root, ".openlanes.coverage.yml"), YAML.dump(reported))

    expect(described_class.load(root)).to be_nil
  end

  %w[command minimum].each do |key|
    it "names a missing #{key}" do
      expect_invalid(printed.except(key), ": missing key #{key}")
    end
  end

  it "refuses an unknown key" do
    expect_invalid(reported.merge("branches" => 90), ": unknown key branches; known: command, report, format, report_command, minimum")
  end

  {
    "neither shape"               => [%w[report format], {}, ": says nowhere to read the figure; give report_command alone, or report with format"],
    "report_command with format"  => [[], { "format" => "lcov" }, ": report_command replaces format; give"],
    "report_command with report"  => [[], { "report" => "r" }, ": report_command replaces report; give"],
    "report_command with both"    => [[], { "report" => "r", "format" => "lcov" }, ": report_command replaces report and format; give"],
    "a report without its format" => [%w[format], {}, ": report without format; give"],
    "a format without its report" => [%w[report], {}, ": format without report; give"]
  }.each do |name, (drop, add, message)|
    it "refuses #{name}" do
      base = add.empty? ? reported : printed
      expect_invalid(base.except(*drop).merge(add), Regexp.escape(message))
    end
  end

  it "refuses an unknown format" do
    expect_invalid(reported.merge("format" => "jacoco"), ".format: \"jacoco\" is not one of lcov, cobertura")
  end

  [-1, 100.5, "95", nil].each do |minimum|
    it "refuses a minimum of #{minimum.inspect}" do
      expect_invalid(printed.merge("minimum" => minimum), ".minimum: #{Regexp.escape(minimum.inspect)} is not a number")
    end
  end

  it "refuses an empty command" do
    expect_invalid(reported.merge("command" => "  "), ".command: must be a non-empty string")
  end

  it "refuses an empty report_command" do
    expect_invalid(printed.merge("report_command" => ""), ".report_command: must be a non-empty string")
  end

  it "refuses a section that is not a mapping" do
    expect_invalid(%w[a b], ": must be a mapping with command, minimum, and report_command alone, or report with format")
  end

  it "refuses an empty section" do
    expect_invalid("coverage:\n", ": must be a mapping")
  end

  it "reports invalid YAML as invalid coverage, naming the file" do
    write("coverage: [unclosed\n")

    expect { described_class.load(root) }.to raise_error(OpenLanes::Coverage::Invalid, /\A#{Regexp.escape(path)}: is not valid YAML/)
  end
end
