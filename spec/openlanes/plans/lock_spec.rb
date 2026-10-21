# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Plans::Lock do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  it "writes this process, this host and the time, and reads them back" do
    written = described_class.write(dir, now: Time.utc(2026, 10, 13, 9))

    expect(described_class.read(dir)).to eq(written)
    expect(written.to_json_hash).to eq(pid: Process.pid, host: Socket.gethostname, started_at: "2026-10-13T09:00:00Z", foreign: false)
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

    expect(File.exist?(described_class.path(dir))).to be(false)
  end

  describe "outside the plan folder" do
    let(:plans) { File.join(dir, ".plans") }
    let(:folder) { File.join(plans, "007.00━━🟡━━❯thing").tap { FileUtils.mkdir_p(it) } }

    def legacy(pid, host: Socket.gethostname)
      File.write(File.join(folder, described_class::FILENAME),
        JSON.generate("pid" => pid, "host" => host, "started_at" => "2026-10-13T09:00:00Z"))
    end

    it "writes into the runtime state directory, named for the ordinal, and nothing into the folder" do
      described_class.write(folder)

      aggregate_failures do
        expect(described_class.path(folder)).to start_with(OpenLanes::Runtime.state_home)
        expect(File.basename(described_class.path(folder))).to eq("007.00.lock")
        expect(Dir.children(folder)).to be_empty
      end
    end

    it "still reads the lock after the folder is renamed" do
      described_class.write(folder)
      renamed = File.join(plans, "007.00━━🎨━━❯thing")
      File.rename(folder, renamed)

      expect(described_class.read(renamed)&.pid).to eq(Process.pid)
    end

    it "reads a legacy locked-by.pid" do
      legacy(Process.ppid)

      expect(described_class.read(folder).pid).to eq(Process.ppid)
    end

    it "keeps a foreign lock held and never stale, and remove leaves it" do
      legacy(1, host: "elsewhere.invalid")
      lock = described_class.read(folder)
      described_class.remove(folder)

      aggregate_failures do
        expect(lock).to be_foreign
        expect(lock).to be_held_elsewhere
        expect(lock).not_to be_stale
        expect(lock.to_json_hash[:foreign]).to be(true)
        expect(File).to exist(File.join(folder, described_class::FILENAME))
      end
    end

    it "removes a legacy lock a dead local process left" do
      dead = Process.spawn("true")
      Process.wait(dead)
      legacy(dead)
      described_class.remove(folder)

      expect(File).not_to exist(File.join(folder, described_class::FILENAME))
    end
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
      File.write(described_class.path(dir), "")

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
