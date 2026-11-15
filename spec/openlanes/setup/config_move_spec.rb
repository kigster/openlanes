# frozen_string_literal: true

require "open3"

RSpec.describe OpenLanes::Setup::ConfigMove do
  subject(:move) { described_class.new(root:) }

  let(:root) { File.realpath(Dir.mktmpdir("openlanes-config-move")) }
  let(:legacy) { File.join(root, OpenLanes::Project::LEGACY_FILE) }
  let(:target) { File.join(root, OpenLanes::Project::FILE) }

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

  before do
    git("init", "-q", "-b", "main")
    File.write(legacy, "jobs: 2\n")
    git("add", ".")
    git("commit", "-qm", "seed")
  end

  after { FileUtils.rm_rf(root) }

  it "previews under dry_run and changes nothing" do
    expect([move.call(dry_run: true), File.exist?(legacy), File.exist?(target)]).to eq([[[legacy, target]], true, false])
  end

  it "moves with git mv, so history follows the file" do
    move.call
    expect(git("status", "--short")).to include("R  .openlanes.yml -> .openlanes/config.yml")
    git("commit", "-qm", "move")
    expect(git("log", "--follow", "--format=%s", "--", ".openlanes/config.yml").split).to eq(%w[move seed])
  end

  it "has nothing to move once moved" do
    move.call
    expect(move.call).to eq([])
  end

  it "refuses when the destination exists" do
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "jobs: 3\n")
    expect { move.call }.to raise_error(OpenLanes::Error, /both .*config\.yml and .*\.openlanes\.yml/)
  end

  # Each of these used to pass the preview and then fail, or half-succeed,
  # in the move itself, so every one is asked under a dry run as well.
  context "when the move cannot be made" do
    # @return [Array<String, Array>] the refusal's message under a dry run and without, or what the call returned
    def refusals
      [true, false].map do |dry_run|
        move.call(dry_run:)
      rescue OpenLanes::Error => e
        e.message
      end
    end

    it "refuses when .openlanes is a regular file, which mkdir would trip over" do
      File.write(File.join(root, OpenLanes::Project::DIR), "x")
      expect(refusals).to all(include('.openlanes is a file, not a folder'))
      expect(File.read(legacy)).to eq("jobs: 2\n")
    end

    it "refuses when the destination is a directory, saying so" do
      FileUtils.mkdir_p(target)
      expect(refusals).to all(include('config.yml is a directory'))
      expect(File.read(legacy)).to eq("jobs: 2\n")
    end

    it "refuses a symlinked source, which would be left pointing at nothing" do
      File.rename(legacy, File.join(root, "real.yml"))
      File.symlink("real.yml", legacy)
      expect(refusals).to all(include('is a symbolic link'))
      expect([File.symlink?(legacy), File.exist?(target)]).to eq([true, false])
    end

    it "refuses a dangling symlink too" do
      File.delete(legacy)
      File.symlink("gone.yml", legacy)
      expect { move.call }.to raise_error(OpenLanes::Error, /is a symbolic link/)
    end
  end
end
