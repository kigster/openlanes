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
    File.write(File.join(dir, ".openlanes.coverage.yml"),
      YAML.dump("command" => command, "report" => report, "format" => format, "minimum" => minimum))
  end

  it "withholds at 94.99% against a 95 minimum and names both numbers" do
    declare(lcov_command(9499))
    verdict = gate.call(checkout:)

    expect(verdict).to have_attributes(passed?: false, percent: 94.99, minimum: 95.0)
    expect(verdict.to_s).to eq("ok-to-merge withheld: coverage 94.99% is below the 95% minimum (lcov: coverage/lcov.info)")
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

  it "withholds when the project declares no coverage" do
    expect(gate.call(checkout:)).to have_attributes(passed?: false, minimum: nil, reason: /no .openlanes.coverage.yml .*M15/)
  end

  it "withholds when the declaration is invalid" do
    File.write(File.join(dir, ".openlanes.coverage.yml"), "command: true\n")

    expect(gate.call(checkout:)).to have_attributes(passed?: false, reason: /missing key report/)
  end
end
