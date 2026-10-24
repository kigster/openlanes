# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::Events::Report, :tree do
  subject(:command) { described_class.new }

  let(:logdir) { File.join(Dir.mktmpdir, "events") }

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(dir: plans_root, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  def config(enabled:)
    OpenLanes::Config.new(events_enabled: enabled, events_dir: logdir)
  end

  def write_log
    FileUtils.mkdir_p(logdir)
    event = OpenLanes::Events::Event.new(event_id: "a",
      kind: "agent_finished",
      at: "2026-10-16T10:00:00Z",
      plan: "001.00",
      agent: "rey",
      adapter: "claude",
      model: "opus",
      payload: { "round" => 1, "status" => "Completed", "cost_usd" => 2.0, "estimated" => true })
    File.write(File.join(logdir, "node.jsonl"), "#{event.to_json}\nnot json\n")
  end

  it "says events are off, and names the config key" do
    allow(OpenLanes::Config).to receive(:load).and_return(config(enabled: false))
    _out, err, status = run
    expect(status).to eq(78)
    expect(err).to include("events: { enabled: true }", ".openlanes.yml")
  end

  it "prints the table on STDOUT" do
    write_log
    allow(OpenLanes::Config).to receive(:load).and_return(config(enabled: true))
    out, _err, status = run
    expect([status, out]).to match([0, a_string_including("completion rate         100.0%", "$2.00 (est.)", "1 unreadable")])
  end

  it "prints JSON with --format json" do
    write_log
    allow(OpenLanes::Config).to receive(:load).and_return(config(enabled: true))
    out, = run(format: "json")
    expect(JSON.parse(out)).to include("runs" => 1, "skipped_lines" => 1)
  end

  it "writes to a file with -o" do
    write_log
    allow(OpenLanes::Config).to receive(:load).and_return(config(enabled: true))
    target = File.join(Dir.mktmpdir, "out", "report.txt")
    out, err, = run(output: target)
    expect([out, File.read(target), err]).to match(["", a_string_including("agent runs finished"), a_string_including("report.txt")])
  end

  it "refuses when no log exists yet" do
    allow(OpenLanes::Config).to receive(:load).and_return(config(enabled: true))
    _out, err, status = run
    expect([status, err]).to match([66, a_string_including("No event log")])
  end
end
