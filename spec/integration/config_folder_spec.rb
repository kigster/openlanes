# frozen_string_literal: true

require "open3"

# Plan 067: the config file moved into `.openlanes/`. Real `exe/openlanes`
# processes in real git projects, nothing stubbed.
RSpec.describe "the config file in the .openlanes folder" do
  let(:exe) { File.expand_path("../../exe/openlanes", __dir__) }
  let(:root) { File.realpath(Dir.mktmpdir("openlanes-config-folder")) }
  let(:commands) { [%w[status], %w[index], %w[resync dirs --dry-run]] }

  def git(*)
    Open3.capture2e("git",
      "-C",
      root,
      "-c",
      "commit.gpgsign=false",
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.com",
      *).first
  end

  def ol(*) = Open3.capture3({ "NO_COLOR" => "1" }, exe, *, chdir: root)

  def write(path, text)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, text)
  end

  before do
    git("init", "-q", "-b", "main")
    FileUtils.mkdir_p(File.join(root, ".plans"))
  end

  after { FileUtils.rm_rf(root) }

  it "runs every command from the legacy file, with one notice per process" do
    write(".openlanes.yml", "jobs: 2\n")
    commands.each do |args|
      _out, err, status = ol(*args)
      expect([args, status.success?, err.scan("has moved to .openlanes/config.yml").size]).to eq([args, true, 1])
    end
  end

  it "refuses every command when both files exist, naming both" do
    write(".openlanes.yml", "jobs: 2\n")
    write(".openlanes/config.yml", "jobs: 3\n")
    commands.reject { it.include?("--help") }.each do |args|
      _out, err, status = ol(*args)
      expect([args, status.success?, err.gsub(/[│\s]+/, "")]).to match([args, false, include(".openlanes/config.yml", ".openlanes.yml")])
    end
  end

  it "moves the file across with config move, after which no notice is printed" do
    write(".openlanes.yml", "jobs: 2\n")
    git("add", ".")
    git("commit", "-qm", "seed")
    ol("config", "move", "--dry-run")
    expect(File.exist?(File.join(root, ".openlanes.yml"))).to be(true)

    ol("config", "move")
    _out, err, status = ol("status")
    expect([git("status", "--short"), status.success?]).to match([include("R  .openlanes.yml -> .openlanes/config.yml"), true])
    expect(err).not_to include("has moved")
  end

  it "resolves this checkout's own config from .openlanes/config.yml" do
    expect(OpenLanes::Project.config_path(File.expand_path("../..", __dir__))).to end_with(".openlanes/config.yml")
  end
end
