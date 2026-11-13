# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe OpenLanes::Vcs::DiffSize do
  let(:dir) { Dir.mktmpdir }

  def git(*) = Open3.capture2e("git", "-C", dir, *).first

  before do
    git("init", "-q", "-b", "main")
    git("config", "user.email", "test@example.com")
    git("config", "user.name", "Test")
    File.write(File.join(dir, "a.txt"), "one\ntwo\n")
    git("add", ".")
    git("commit", "-qm", "base")
    git("branch", "base")
  end

  after { FileUtils.rm_rf(dir) }

  it "counts insertions plus deletions against the base" do
    File.write(File.join(dir, "a.txt"), "one\nthree\nfour\n")
    git("commit", "-qam", "change")
    expect(described_class.lines(dir, base: "base")).to eq(3)
  end

  it "is zero for a branch with no change" do
    expect(described_class.lines(dir, base: "base")).to eq(0)
  end

  it "is nil when the base does not exist" do
    expect(described_class.lines(dir)).to be_nil
  end

  it "is nil on a machine where git cannot be run" do
    allow(Open3).to receive(:capture2).and_raise(Errno::ENOENT, "git")
    expect(described_class.lines(dir, base: "base")).to be_nil
  end
end
