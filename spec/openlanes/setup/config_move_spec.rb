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
end
