# frozen_string_literal: true

require "bundler"
require "fileutils"
require "open3"
require "tmpdir"

# bin/bump-version is run for real, `bundle lock` included, against a copy of
# the four files a relock reads. The checkout itself is never touched.
RSpec.describe "bin/bump-version" do
  let(:root) { File.expand_path("../../..", __dir__) }
  let(:script) { File.join(root, "bin", "bump-version") }
  let(:copied) { %w[lib/openlanes/version.rb Gemfile Gemfile.lock openlanes.gemspec] }

  let(:dir) { Dir.mktmpdir("bump-version") }

  before do
    copied.each do |file|
      FileUtils.mkdir_p(File.join(dir, File.dirname(file)))
      FileUtils.cp(File.join(root, file), File.join(dir, file))
    end
  end

  after { FileUtils.remove_entry(dir) }

  # Unbundled, so the script's own `bundle lock` sees the copy's Gemfile and
  # not the one rspec was launched under.
  def bump(*)
    Bundler.with_unbundled_env { Open3.capture3(RbConfig.ruby, script, *, chdir: dir) }
  end

  def version_rb = File.read(File.join(dir, "lib/openlanes/version.rb"))
  def lock = File.read(File.join(dir, "Gemfile.lock"))
  def locked = OpenLanes::Release::Lockfile.new(lock).versions

  it "rewrites VERSION and relocks, so both files carry the new version" do
    _out, err, status = bump("9.8.7")

    expect(status).to be_success, err
    expect(version_rb).to include('VERSION = "9.8.7"')
    expect(locked).to eq(["9.8.7"])
  end

  it "refuses a version that is not MAJOR.MINOR.PATCH, and writes nothing" do
    before = [version_rb, lock]

    %w[9.8 v9.8.7 9.8.7.pre 9.8.x].each do |malformed|
      _out, err, status = bump(malformed)

      expect(status).not_to be_success
      expect(err).to include("is not MAJOR.MINOR.PATCH")
    end
    expect([version_rb, lock]).to eq(before)
  end

  it "refuses to run without a version" do
    _out, err, status = bump

    expect(status).not_to be_success
    expect(err).to include("usage:")
  end

  it "prints the change on --dry-run and leaves both files unchanged" do
    before = [version_rb, lock]

    out, err, status = bump("9.8.7", "--dry-run")

    expect(status).to be_success, err
    expect(out).to include("-> 9.8.7").and include("nothing written")
    expect([version_rb, lock]).to eq(before)
  end
end
