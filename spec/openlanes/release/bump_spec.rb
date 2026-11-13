# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# The steps around `bundle lock`, with the relock replaced by a lambda that
# writes whatever lock the example wants. bump_version_spec.rb runs the real one.
RSpec.describe OpenLanes::Release::Bump do
  subject(:bump) { described_class.new(root: dir, relock:) }

  let(:dir) { Dir.mktmpdir("release-bump") }
  let(:lock_text) { ->(v) { "PATH\n  specs:\n    openlanes (#{v})\n\nCHECKSUMS\n  openlanes (#{v})\n" } }
  let(:relock) { -> { write(OpenLanes::Release::Lockfile::PATH, lock_text.call("9.8.7")) || true } }

  def write(file, text)
    FileUtils.mkdir_p(File.join(dir, File.dirname(file)))
    File.write(File.join(dir, file), text)
    nil
  end

  def read(file) = File.read(File.join(dir, file))

  before do
    write(OpenLanes::Release::VersionFile::PATH, %(module OpenLanes\n  VERSION = "1.2.3"\nend\n))
    write(OpenLanes::Release::Lockfile::PATH, lock_text.call("1.2.3"))
    write("Gemfile", "")
  end

  after { FileUtils.remove_entry(dir) }

  it "rewrites VERSION, relocks, and reports both files agree" do
    expect(bump.call("9.8.7")).to eq(["openlanes 1.2.3 -> 9.8.7: lib/openlanes/version.rb and Gemfile.lock agree"])
    expect(read(OpenLanes::Release::VersionFile::PATH)).to include('VERSION = "9.8.7"')
  end

  it "previews on dry_run, without relocking or writing" do
    relocked = false
    lines = described_class.new(root: dir, relock: -> { relocked = true }).call("9.8.7", dry_run: true)

    expected = [
      "lib/openlanes/version.rb: 1.2.3 -> 9.8.7",
      "Gemfile.lock: openlanes (1.2.3) -> openlanes (9.8.7)",
      "dry run: nothing written"
    ]
    expect(lines).to eq(expected)
    expect(relocked).to be(false)
    expect(read(OpenLanes::Release::VersionFile::PATH)).to include('VERSION = "1.2.3"')
  end

  it "refuses a malformed version before writing anything" do
    expect { bump.call("9.8") }.to raise_error(OpenLanes::Release::Failed, /is not MAJOR.MINOR.PATCH/)
    expect(read(OpenLanes::Release::VersionFile::PATH)).to include('VERSION = "1.2.3"')
  end

  it "names a missing file" do
    File.delete(File.join(dir, "Gemfile"))

    expect { bump.call("9.8.7") }.to raise_error(OpenLanes::Release::Failed, /Gemfile not found/)
  end

  it "refuses a version.rb with no VERSION assignment" do
    write(OpenLanes::Release::VersionFile::PATH, "module OpenLanes; end\n")

    expect { bump.call("9.8.7") }.to raise_error(OpenLanes::Release::Failed, /no VERSION assignment/)
  end

  it "fails when bundle lock fails" do
    failing = described_class.new(root: dir, relock: -> { false })

    expect { failing.call("9.8.7") }.to raise_error(OpenLanes::Release::Failed, /bundle lock failed/)
  end

  it "fails when the lock still disagrees after relocking" do
    stale = described_class.new(root: dir, relock: -> { true })

    expect { stale.call("9.8.7") }
      .to raise_error(OpenLanes::Release::Failed, /still says openlanes \(1\.2\.3\), not 9\.8\.7/)
  end

  it "is what the facade runs" do
    expect(OpenLanes::Release.bump(root: dir, version: "9.8.7", relock:).first).to include("agree")
  end
end
