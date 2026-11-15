# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::ConfigFile::Move do
  subject(:command) { described_class.new }

  let(:root) { File.realpath(Dir.mktmpdir("openlanes-config-move-cli")) }
  let(:legacy) { File.join(root, OpenLanes::Project::LEGACY_FILE) }
  let(:target) { File.join(root, OpenLanes::Project::FILE) }

  around do |example|
    Dir.chdir(root) { example.run }
  ensure
    FileUtils.rm_rf(root)
  end

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = swap_streams(out, err) { command.call(dry_run: false, **) }
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  # @return [Integer] the exit status, 0 when the command returned
  def swap_streams(out, err)
    original = [$stdout, $stderr]
    $stdout, $stderr = out, err
    yield
    0
  rescue SystemExit => e
    e.status
  ensure
    $stdout, $stderr = original
  end

  it "prints the move under --dry-run and changes nothing" do
    File.write(legacy, "jobs: 2\n")
    out, _err, status = run(dry_run: true)
    expect([out, status, File.exist?(legacy), File.exist?(target)])
      .to eq(["would move #{legacy} -> #{target}\n", 0, true, false])
  end

  it "moves the file" do
    File.write(legacy, "jobs: 2\n")
    out, = run
    expect([out, File.read(target), File.exist?(legacy)]).to eq(["moved #{legacy} -> #{target}\n", "jobs: 2\n", false])
  end

  it "says there is nothing to move in a project without the legacy file" do
    FileUtils.mkdir_p(File.join(root, ".git"))
    _out, err, status = run
    expect([err, status]).to match([include("Nothing to move"), 0])
  end

  it "refuses when both files exist" do
    File.write(legacy, "jobs: 2\n")
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "jobs: 3\n")
    _out, err, status = run
    expect([status, err.gsub(/[│\s]+/, "")]).to match([65, include("both")])
  end

  # The command's own refusals: loading the config already refuses two
  # files, so only what is not a file at either path reaches the mover.
  it "refuses when a directory sits at the destination, under --dry-run too" do
    File.write(legacy, "jobs: 2\n")
    FileUtils.mkdir_p(target)
    [false, true].each do |dry_run|
      out, err, status = run(dry_run:)
      expect([out, status, err.gsub(/[│\s]+/, ""), File.read(legacy)]).to match(["", 65, include("isadirectory"), "jobs: 2\n"])
    end
  end

  it "refuses with the same exit when .openlanes is a regular file, under --dry-run too" do
    File.write(legacy, "jobs: 2\n")
    File.write(File.join(root, OpenLanes::Project::DIR), "x")
    [false, true].each do |dry_run|
      out, err, status = run(dry_run:)
      expect([out, status, err.gsub(/[│\s]+/, "")]).to match(["", 65, include("isafile,notafolder")])
    end
  end

  it "refuses a symlinked legacy file and leaves the link alone" do
    File.write(File.join(root, "real.yml"), "jobs: 2\n")
    File.symlink("real.yml", legacy)
    [false, true].each do |dry_run|
      out, err, status = run(dry_run:)
      expect([out, status, err.gsub(/[│\s]+/, ""), File.symlink?(legacy)]).to match(["", 65, include("isasymboliclink"), true])
    end
  end
end
