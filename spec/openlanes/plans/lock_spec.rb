# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Plans::Lock do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  it "writes this process, this host and the time, and reads them back" do
    written = described_class.write(dir, now: Time.utc(2026, 10, 13, 9))

    expect(described_class.read(dir)).to eq(written)
    expect(written.to_json_hash).to eq(pid: Process.pid, host: Socket.gethostname, started_at: "2026-10-13T09:00:00Z")
  end

  it "reads nothing when there is no lock" do
    expect(described_class.read(dir)).to be_nil
  end

  it "reads a malformed file as no lock" do
    File.write(File.join(dir, described_class::FILENAME), "not json")

    expect(described_class.read(dir)).to be_nil
  end

  it "removes the file" do
    described_class.write(dir)
    described_class.remove(dir)

    expect(File.exist?(File.join(dir, described_class::FILENAME))).to be(false)
  end

  describe "#alive?" do
    it "is true for a live process on this host" do
      expect(described_class.write(dir)).to be_alive
    end

    it "is false for a dead process on this host" do
      pid = Process.spawn("true")
      Process.wait(pid)

      expect(described_class.write(dir, pid:)).not_to be_alive
    end

    it "is never declared dead from another host" do
      lock = described_class.new(pid: Process.pid, host: "elsewhere.invalid", started_at: Time.now)

      expect([lock.local?, lock.alive?]).to eq([false, false])
    end
  end
end
