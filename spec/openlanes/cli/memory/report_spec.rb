# frozen_string_literal: true

# `openlanes memory report` reads the event log and nothing else. With the
# log off it must say the counts are unavailable, never print zeros.
RSpec.describe OpenLanes::CLI::Memory::Report do
  subject(:command) { described_class.new }

  let(:root) { Dir.mktmpdir("project").tap { FileUtils.mkdir_p(File.join(it, ".plans")) } }
  let(:dir) { File.join(root, OpenLanes::Memory::PROJECT_DIR) }
  let(:log_dir) { Dir.mktmpdir("memory-report-events") }

  after { FileUtils.rm_rf([root, log_dir]) }

  def report
    out = CapturedStream.new
    err = CapturedStream.new
    status = swapping_streams(out, err) { Dir.chdir(root) { command.call } }
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  # @return [Integer] the exit status a refusal raised, else 0
  def swapping_streams(out, err)
    original = [$stdout, $stderr]
    $stdout, $stderr = out, err
    yield
    0
  rescue SystemExit => e
    e.status
  ensure
    $stdout, $stderr = original
  end

  def events_on
    FileUtils.mkdir_p(File.join(root, ".openlanes"))
    File.write(File.join(root, OpenLanes::Project::FILE), "project: demo\nevents:\n  enabled: true\n  dir: #{log_dir}\n")
  end

  def record(kind, plan, lesson, at: Time.utc(2026, 11, 14, 9))
    sink = OpenLanes::Events::Sink.new(dir: log_dir, node: "n1", checkout: "c1", project: "demo", run: "r1", clock: -> { at })
    sink.record(kind, plan:, round: 1, agent: "backend-coder", seq: lesson, lesson:)
  end

  before do
    write_lesson(dir, "L-0001", lesson_meta("L-0001", title: "Run redis specs alone"))
    write_lesson(dir, "L-0002", lesson_meta("L-0002", title: "Name the reader"))
  end

  it "says the counts are unavailable when events are off, and prints no zeros" do
    publish_lessons(root)

    out, err, status = report
    expect(status).to eq(78)
    expect(err).to include("Citation counts are unavailable: events are off")
    expect(out).to eq("")
  end

  it "shows each lesson with the plans it was offered on and cited on, and when it was last cited" do
    events_on
    publish_lessons(root)
    record(:lesson_offered, "001.00", "L-0001")
    record(:lesson_offered, "002.00", "L-0001")
    record(:lesson_cited, "002.00", "L-0001")
    record(:lesson_offered, "002.00", "L-0002")

    out, _, status = report
    rows = out.lines.map(&:split)
    expect(status).to eq(0)
    expect(rows.first).to eq(%w[ID TITLE OFFERED CITED LAST_CITED])
    expect(out).to match(/^L-0001\s+Run redis specs alone\s+2\s+1\s+2026-11-14$/)
    expect(out).to match(/^L-0002\s+Name the reader\s+1\s+0\s+never$/)
  end

  it "shows zeros once the log is on but no run has recorded a lesson yet" do
    events_on
    publish_lessons(root)
    FileUtils.rm_rf(log_dir)

    expect(report.first).to match(/^L-0001\s+Run redis specs alone\s+0\s+0\s+never$/)
  end
end
