# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Coverage::Config do
  let(:root) { Dir.mktmpdir("coverage-config") }
  let(:path) { File.join(root, ".openlanes.coverage.yml") }
  let(:valid) do
    { "command" => "bundle exec rspec", "report" => "coverage/.resultset.json", "format" => "simplecov", "minimum" => 95 }
  end

  after { FileUtils.remove_entry(root) }

  def write(settings) = File.write(path, settings.is_a?(String) ? settings : YAML.dump(settings))

  def expect_invalid(settings, message)
    write(settings)
    expect { described_class.load(root) }.to raise_error(OpenLanes::Coverage::Invalid, /\A#{Regexp.escape(path)}: .*#{message}/)
  end

  it "reads the four keys" do
    write(valid)
    config = OpenLanes::Coverage.config(root)

    expect(config).to have_attributes(path:,
      command: "bundle exec rspec",
      report: "coverage/.resultset.json",
      format: :simplecov,
      minimum: 95.0)
    expect(config.report_path(root)).to eq(File.join(root, "coverage/.resultset.json"))
  end

  it "accepts a fractional minimum and the bounds" do
    [0, 100, 94.5].each do |minimum|
      write(valid.merge("minimum" => minimum))
      expect(described_class.load(root).minimum).to eq(minimum.to_f)
    end
  end

  it "is nil when the project declares nothing" do
    expect(described_class.load(root)).to be_nil
  end

  described_class::KEYS.each do |key|
    it "names a missing #{key}" do
      expect_invalid(valid.except(key), "missing key #{key}")
    end
  end

  it "refuses an unknown key" do
    expect_invalid(valid.merge("branches" => 90), "unknown key branches")
  end

  it "refuses an unknown format" do
    expect_invalid(valid.merge("format" => "jacoco"), "format: \"jacoco\" is not one of lcov, cobertura")
  end

  [-1, 100.5, "95", nil].each do |minimum|
    it "refuses a minimum of #{minimum.inspect}" do
      expect_invalid(valid.merge("minimum" => minimum), "minimum: #{Regexp.escape(minimum.inspect)} is not a number")
    end
  end

  it "refuses an empty command" do
    expect_invalid(valid.merge("command" => "  "), "command: must be a non-empty string")
  end

  it "refuses a file that is not a mapping" do
    expect_invalid("- a\n- b\n", "expected a mapping")
  end

  it "refuses invalid YAML" do
    expect_invalid("command: [unclosed\n", "is not valid YAML")
  end
end
