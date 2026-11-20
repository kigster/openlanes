# frozen_string_literal: true

RSpec.describe OpenLanes::Memory::Uptake do
  let(:root) { Dir.mktmpdir("uptake-root") }
  let(:log_dir) { Dir.mktmpdir("uptake-events") }

  after { FileUtils.rm_rf([root, log_dir]) }

  def config(**events) = OpenLanes::Config.new(events_enabled: events.fetch(:enabled, true), events_dir: log_dir, project: "demo")

  it "is nil with the event log off, so nobody reads unavailable counts as zeros" do
    expect(described_class.read(root:, config: config(enabled: false))).to be_nil
  end

  it "is empty with the log on and nothing recorded yet" do
    FileUtils.rm_rf(log_dir)

    expect(described_class.read(root:, config: config)).to eq({})
  end

  it "counts this project's offers and citations from the log" do
    sink = OpenLanes::Events::Sink.new(dir: log_dir, node: "n1", checkout: "c1", project: "demo", run: "r1")
    sink.record(:lesson_offered, plan: "001.00", round: 1, agent: "backend-coder", seq: "L-0007", lesson: "L-0007")
    sink.record(:lesson_cited, plan: "001.00", round: 1, agent: "backend-coder", seq: "L-0007", lesson: "L-0007")
    other = OpenLanes::Events::Sink.new(dir: log_dir, node: "n2", checkout: "c2", project: "elsewhere", run: "r2")
    other.record(:lesson_offered, plan: "002.00", round: 1, agent: "backend-coder", seq: "L-0007", lesson: "L-0007")

    expect(described_class.read(root:, config: config)["L-0007"]).to have_attributes(offered: 1, cited: 1)
  end
end
