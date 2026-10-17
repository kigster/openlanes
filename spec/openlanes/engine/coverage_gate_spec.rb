# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Engine::CoverageGate do
  subject(:gate) { OpenLanes::Engine.coverage_gate(timeout: 10) }

  let(:dir) { File.realpath(Dir.mktmpdir("coverage-gate")) }
  let(:dirty) { false }
  let(:checkout) { instance_double(OpenLanes::Vcs::Worktree::Checkout, path: dir, dirty?: dirty) }
  let(:minimum) { 95 }

  after { FileUtils.remove_entry(dir) }

  # A command that writes an lcov report with `hit` of 10_000 lines covered.
  def lcov_command(hit, exit_with: 0)
    "pwd > ran-in && mkdir -p coverage && " \
      "printf 'SF:lib/a.rb\\nLF:10000\\nLH:#{hit}\\nend_of_record\\n' > coverage/lcov.info && exit #{exit_with}"
  end

  def declare(command, report: "coverage/lcov.info", format: "lcov")
    section("command" => command, "report" => report, "format" => format, "minimum" => minimum)
  end

  def section(coverage) = File.write(File.join(dir, ".openlanes.yml"), YAML.dump("coverage" => coverage))

  def printing(report_command, command: "true")
    section("command" => command, "report_command" => report_command, "minimum" => minimum)
  end

  it "withholds at 94.99% against a 95 minimum and names both numbers" do
    declare(lcov_command(9499))
    verdict = gate.call(checkout:)

    expect(verdict).to have_attributes(passed?: false, percent: 94.99, minimum: 95.0)
    expect(verdict.to_s).to eq("ready-to-merge withheld: coverage 94.99% is below the 95% minimum (lcov: coverage/lcov.info)")
  end

  it "passes at exactly 95.0%" do
    declare(lcov_command(9500))
    verdict = gate.call(checkout:)

    expect(verdict).to have_attributes(passed?: true, withheld?: false, percent: 95.0)
    expect(verdict.to_s).to eq("coverage 95.00% meets the 95% minimum (lcov: coverage/lcov.info)")
  end

  it "never prints a figure that rounds up past the minimum" do
    expect(described_class.figure(94.995)).to eq("94.99%")
  end

  # `10.03 * 100` is 1002.9999999999999, so flooring the Float product
  # printed 10.02%; 573 of the 10001 two-decimal figures misprinted that way.
  it "prints every two-decimal figure as itself, from the counts or from a Float" do
    misprinted = (0..10_000).reject do |hundredths|
      expected = format("%.2f%%", hundredths / 100.0)
      described_class.figure(OpenLanes::Coverage::Report.new(covered: hundredths, relevant: 10_000).ratio) == expected &&
        described_class.figure(hundredths / 100.0) == expected
    end

    expect(misprinted).to be_empty
  end

  it "reports 10.03% when the counts say 10.03%" do
    declare(lcov_command(1003))

    expect(gate.call(checkout:).to_s).to include("coverage 10.03% is below the 95% minimum")
  end

  it "runs the command in the checkout it was handed" do
    declare(lcov_command(9500))
    gate.call(checkout:)

    expect(File.read(File.join(dir, "ran-in")).strip).to eq(dir)
  end

  it "counts a non-zero exit as 0% even when the report passes" do
    declare(lcov_command(10_000, exit_with: 3))
    verdict = gate.call(checkout:)

    expect(verdict).to have_attributes(passed?: false, percent: 0.0, reason: /0%: `.*` exited 3/)
  end

  it "keeps the tail of the command's output" do
    declare("seq 1 50; exit 1")

    expect(gate.call(checkout:).output).to eq((31..50).map(&:to_s))
  end

  it "stops a command that runs past the timeout and counts it as 0%" do
    declare("sleep 30")
    verdict = OpenLanes::Engine.coverage_gate(timeout: 0.3).call(checkout:)

    expect(verdict).to have_attributes(passed?: false, reason: /ran past 0.3s and was stopped/)
  end

  it "counts a report the command did not write as stale" do
    FileUtils.mkdir_p(File.join(dir, "coverage"))
    File.write(File.join(dir, "coverage/lcov.info"), "SF:a\nLF:1\nLH:1\nend_of_record\n")
    File.utime(Time.now - 60, Time.now - 60, File.join(dir, "coverage/lcov.info"))
    declare("true")

    expect(gate.call(checkout:)).to have_attributes(passed?: false, reason: /older than this run/)
  end

  it "counts a missing report as 0%" do
    declare("true")

    expect(gate.call(checkout:)).to have_attributes(passed?: false, percent: 0.0, reason: %r{0%: .*coverage/lcov.info is missing})
  end

  context "with a dirty checkout" do
    let(:dirty) { true }

    it "withholds without running anything" do
      declare(lcov_command(10_000))

      expect(gate.call(checkout:)).to have_attributes(passed?: false, reason: /uncommitted changes/)
      expect(File).not_to exist(File.join(dir, "ran-in"))
    end
  end

  it "withholds as unconfigured when .openlanes.yml has no coverage: section" do
    File.write(File.join(dir, ".openlanes.yml"), "jobs: 2\n")
    verdict = gate.call(checkout:)

    expect(verdict).to have_attributes(passed?: false,
      unconfigured?: true,
      minimum: nil,
      reason: ".openlanes.yml in #{dir} has no coverage: section, so nothing was measured")
  end

  it "withholds as unconfigured when there is no .openlanes.yml at all" do
    expect(gate.call(checkout:)).to have_attributes(passed?: false, unconfigured?: true)
  end

  it "withholds, configured, when the section is invalid" do
    File.write(File.join(dir, ".openlanes.yml"), "coverage:\n  command: true\n")

    expect(gate.call(checkout:)).to have_attributes(passed?: false, unconfigured?: false, reason: /coverage: missing key minimum/)
  end

  it "withholds, configured, when the file around the section is invalid" do
    File.write(File.join(dir, ".openlanes.yml"), "jobs: many\n")

    expect(gate.call(checkout:)).to have_attributes(passed?: false, unconfigured?: false, reason: /jobs: "many"/)
  end

  context "with a report_command" do
    it "passes on the figure it prints, after the command ran" do
      printing("echo 98.785", command: "touch ran")
      verdict = gate.call(checkout:)

      expect(verdict).to have_attributes(passed?: true, percent: 98.785)
      expect(verdict.to_s).to eq("coverage 98.78% meets the 95% minimum (report_command: `echo 98.785`)")
      expect(File).to exist(File.join(dir, "ran"))
    end

    it "withholds below the minimum and floors the figure" do
      printing("echo 94.999")

      expect(gate.call(checkout:).to_s).to eq("ready-to-merge withheld: coverage 94.99% is below the 95% minimum (report_command: `echo 94.999`)")
    end

    it "reads the figure in the checkout, from STDOUT alone" do
      File.write(File.join(dir, "figure"), "97\n")
      printing("echo 'jq: a warning' >&2; cat figure")

      expect(gate.call(checkout:)).to have_attributes(passed?: true, percent: 97.0)
    end

    [["echo n/a", 'printed "n/a"'], ["printf ''", 'printed ""'], ["echo 100.5", 'printed "100.5"'],
     ["echo '95 97'", 'printed "95 97"']].each do |command, said|
      it "counts #{command.inspect} as an unreadable report, at 0%" do
        printing(command)

        expect(gate.call(checkout:)).to have_attributes(passed?: false,
          percent: 0.0,
          reason: "coverage counts as 0%: `#{command}` #{said}, not a line percentage")
      end
    end

    it "counts a failing report_command as 0%, with the first line it wrote to STDERR" do
      printing("echo 'no such file' >&2; exit 4")

      expect(gate.call(checkout:)).to have_attributes(passed?: false,
        percent: 0.0,
        reason: /0%: `.*` exited 4, not a line percentage \(no such file\)/)
    end

    it "stops a report_command that runs past the timeout" do
      printing("sleep 30")
      verdict = OpenLanes::Engine.coverage_gate(timeout: 0.3).call(checkout:)

      expect(verdict).to have_attributes(passed?: false, reason: /0%: `sleep 30` ran past 0.3s/)
    end

    it "never runs the report_command when the test command fails" do
      printing("touch read && echo 99", command: "exit 1")

      expect(gate.call(checkout:)).to have_attributes(passed?: false, reason: /`exit 1` exited 1/)
      expect(File).not_to exist(File.join(dir, "read"))
    end
  end
end
