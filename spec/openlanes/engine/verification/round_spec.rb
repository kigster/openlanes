# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Verification::Round do
  let(:plan_dir) { Dir.mktmpdir("openlanes-round") }

  after { FileUtils.rm_rf(plan_dir) }

  def round(number, report: false)
    dir = File.join(plan_dir, "verification", number.to_s)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "report.md"), "Verdict: verified\n") if report
  end

  it "starts at 1 in a plan never verified" do
    expect(described_class.next(plan_dir)).to have_attributes(number: 1, reported?: false)
  end

  it "goes on to the next number once the newest round has its report" do
    round(1, report: true)

    expect(described_class.next(plan_dir).number).to eq(2)
  end

  it "hands an unreported round to the next run, rather than leaving a gap" do
    round(1, report: true)
    round(2)

    expect(described_class.next(plan_dir).number).to eq(2)
  end

  it "orders rounds by number, not by name, and ignores anything else in the folder" do
    [2, 10, 1].each { round(it, report: true) }
    FileUtils.mkdir_p(File.join(plan_dir, "verification", "notes"))

    expect(described_class.all(plan_dir).map(&:number)).to eq([1, 2, 10])
  end

  it "reads its report back" do
    round(1, report: true)

    expect(described_class.latest(plan_dir).report.verdict).to eq(:verified)
  end

  it "names its folder relative to the plan" do
    expect(described_class.new(plan_dir:, number: 3).relative).to eq("verification/3")
  end
end
