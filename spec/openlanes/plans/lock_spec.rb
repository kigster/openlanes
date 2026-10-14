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

  # A plain File.write let two runs that both saw no lock both claim the
  # plan, and the later one won in silence.
  describe ".write as a claim" do
    let(:file) { File.join(dir, described_class::FILENAME) }

    def lock_by(pid, host: Socket.gethostname)
      File.write(file, JSON.generate("pid" => pid, "host" => host, "started_at" => "2026-10-13T09:00:00Z"))
    end

    {
      "a live process on this host" => -> { Process.ppid },
      "a process on another host"   => -> { 1 }
    }.each do |holder, pid|
      it "refuses a plan held by #{holder}, and leaves its lock alone" do
        host = holder.include?("another") ? "elsewhere.invalid" : Socket.gethostname
        lock_by(pid.call, host:)

        aggregate_failures do
          expect { described_class.write(dir) }.to raise_error(described_class::Held, /locked by pid #{pid.call}/)
          expect(described_class.read(dir).pid).to eq(pid.call)
        end
      end
    end

    it "removes a lock left by a dead process on this host, and claims" do
      dead = Process.spawn("true")
      Process.wait(dead)
      lock_by(dead)

      expect(described_class.write(dir).pid).to eq(Process.pid)
      expect(described_class.read(dir).pid).to eq(Process.pid)
    end

    it "rewrites a lock this process already holds" do
      described_class.write(dir, now: Time.utc(2026, 10, 13, 9))

      expect(described_class.write(dir, now: Time.utc(2026, 10, 13, 10)).started_at).to eq(Time.utc(2026, 10, 13, 10))
      expect(described_class.read(dir).started_at).to eq(Time.utc(2026, 10, 13, 10))
    end

    # Between another run's O_EXCL create and its write the file is empty.
    it "refuses an unreadable lock young enough to be mid-write" do
      File.write(file, "")

      expect { described_class.write(dir) }.to raise_error(described_class::Held, /unreadable/)
    end

    it "clears an unreadable lock old enough to be debris, and claims" do
      File.write(file, "not json")
      old = Time.now - described_class::UNREADABLE_GRACE - 1
      File.utime(old, old, file)

      expect(described_class.write(dir).pid).to eq(Process.pid)
    end

    # Each claimant names a different live process, as eight runs would.
    it "lets only one of many concurrent claims win" do
      live = Array.new(8) { Process.spawn("sleep", "30") }
      results = live.map do |pid|
        Thread.new do
          described_class.write(dir, pid:)
          :won
        rescue described_class::Held
          :lost
        end
      end.map(&:value)

      expect(results.count(:won)).to eq(1)
    ensure
      live&.each do |pid|
        Process.kill(:KILL, pid)
        Process.wait(pid)
      end
    end
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
