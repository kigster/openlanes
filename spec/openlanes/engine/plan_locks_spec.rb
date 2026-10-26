# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Engine::PlanLocks do
  subject(:locks) { described_class.new }

  let(:dir) { Dir.mktmpdir }
  let(:file) { OpenLanes::Plans::Lock.path(dir) }

  after { FileUtils.rm_rf(dir) }

  # Both halves of a pair hold one folder: the first to finish must not
  # take the lock away from the one still working.
  it "keeps the lock until the last holder of the plan releases it" do
    locks.hold("001.00", dir)
    locks.hold("001.00", dir)
    locks.release("001.00")

    aggregate_failures do
      expect(File).to exist(file)
      expect(locks.count("001.00")).to eq(1)
    end

    locks.release("001.00")
    expect(File).not_to exist(file)
  end

  # The partner's hold must not trip over the lock its own pair just wrote.
  it "lets a pair share the lock its first half claimed" do
    locks.hold("001.00", dir)

    expect { locks.hold("001.00", dir) }.not_to raise_error
    expect(locks.count("001.00")).to eq(2)
  end

  it "counts nothing when another live run holds the plan" do
    File.write(file, JSON.generate("pid" => Process.ppid, "host" => Socket.gethostname, "started_at" => "2026-10-13T09:00:00Z"))

    aggregate_failures do
      expect { locks.hold("001.00", dir) }.to raise_error(OpenLanes::Plans::Lock::Held)
      expect(locks.count("001.00")).to eq(0)
      expect(OpenLanes::Plans::Lock.read(dir).pid).to eq(Process.ppid)
    end
  end

  it "ignores a release for a plan nobody holds" do
    expect { locks.release("002.00") }.not_to raise_error
  end

  it "rewrites the lock at a folder's new path" do
    other = Dir.mktmpdir
    locks.hold("001.00", dir)
    locks.hold("001.00", other)
    locks.release("001.00")
    locks.release("001.00")

    expect(File).not_to exist(File.join(other, OpenLanes::Plans::Lock::FILENAME))
  ensure
    FileUtils.rm_rf(other)
  end

  # W31: the plan's alock follows the lock file's count, and is taken before
  # the start renames the folder.
  context "with alock" do
    subject(:locks) { described_class.new(agent_locks:) }

    let(:agent_locks) { instance_double(OpenLanes::Engine::AgentLocks, acquire: true, release: nil) }
    let(:renamed) { "#{dir}-renamed" }

    after { FileUtils.rm_rf(renamed) }

    it "reserves the folder, keeps it while a pair works, and gives it back with the last" do
      locks.reserve("001.00", dir, "openlanes: backend-coder on 001.00")
      locks.hold("001.00", dir)
      locks.reserve("001.00", dir, "openlanes: frontend-coder on 001.00")
      locks.hold("001.00", dir)
      locks.release("001.00")

      aggregate_failures do
        expect(agent_locks).to have_received(:acquire).with(dir, "openlanes: backend-coder on 001.00").once
        expect(agent_locks).not_to have_received(:release)
      end

      locks.release("001.00")
      expect(agent_locks).to have_received(:release).with(dir).once
    end

    it "refuses a plan somebody else holds, and holds nothing for it" do
      allow(agent_locks).to receive(:acquire).and_return(false)

      aggregate_failures do
        expect { locks.reserve("001.00", dir, "x") }.to raise_error(described_class::Refused, /held in alock/)
        expect(locks.count("001.00")).to eq(0)
        expect(File).not_to exist(file)
      end
    end

    it "moves the alock to the folder's new name, taking the new before giving back the old" do
      locks.reserve("001.00", dir, "x")
      FileUtils.mv(dir, renamed)
      locks.hold("001.00", renamed)

      aggregate_failures do
        expect(agent_locks).to have_received(:acquire).with(renamed, "openlanes").ordered
        expect(agent_locks).to have_received(:release).with(dir).ordered
      end
    end

    it "gives the alock back when another run already holds the lock file" do
      OpenLanes::Plans::Lock.write(dir, pid: Process.pid + 1_000_000)
      allow(OpenLanes::Plans::Lock).to receive(:write).and_raise(OpenLanes::Plans::Lock::Held, "held")
      locks.reserve("001.00", dir, "x")

      aggregate_failures do
        expect { locks.hold("001.00", dir) }.to raise_error(OpenLanes::Plans::Lock::Held)
        expect(agent_locks).to have_received(:release).with(dir)
      end
    end

    it "gives back a reservation whose job never started" do
      locks.reserve("001.00", dir, "x")
      locks.unreserve("001.00")

      expect(agent_locks).to have_received(:release).with(dir)
    end
  end
end
