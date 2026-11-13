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
end
