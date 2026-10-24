# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Events::Log do
  let(:dir) { Dir.mktmpdir("log") }

  after { FileUtils.rm_rf(dir) }

  def line(id, kind = "run_started", at = "2026-10-16T12:00:00.000Z")
    OpenLanes::Events::Event.new(event_id: id, kind:, at:).to_json
  end

  it "merges node files and keeps one event per event_id, oldest first" do
    File.write(File.join(dir, "n1.jsonl"), "#{line("b", "run_finished", "2026-10-16T13:00:00.000Z")}\n#{line("a")}\n")
    File.write(File.join(dir, "n2.jsonl"), "#{line("a")}\n")

    log = described_class.new(dir:)
    expect(log.events.map(&:event_id)).to eq(%w[a b])
    expect(log.files.size).to eq(2)
    expect(log.skipped_lines).to eq(0)
  end

  it "skips and counts lines that are not events" do
    File.write(File.join(dir, "n1.jsonl"),
      "#{line("a")}\n{not json\n\n#{JSON.generate(kind: "chat", event_id: "x", at: "t")}\n[1]\n")

    log = described_class.new(dir:)
    expect(log.events.map(&:event_id)).to eq(%w[a])
    expect(log.skipped_lines).to eq(3)
  end

  it "reads nothing from a directory that does not exist" do
    log = described_class.new(dir: File.join(dir, "missing"))

    expect(log.exist?).to be(false)
    expect(log.events).to eq([])
  end
end
