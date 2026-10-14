# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Engine::PlanLocks do
  subject(:locks) { described_class.new }

  let(:dir) { Dir.mktmpdir }
  let(:file) { File.join(dir, OpenLanes::Plans::Lock::FILENAME) }

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
end
