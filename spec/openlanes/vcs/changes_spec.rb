# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Vcs::Changes do
  subject(:changes) { described_class.new(worktree:, base: ->(_) { "base" }) }

  let(:repo) { Dir.mktmpdir("openlanes-changes") }
  let(:worktree) { Struct.new(:path) { def path_for(_) = path }.new(repo) }
  let(:subject_double) { Struct.new(:feature).new(:feature) }

  def git(*) = system("git", "-C", repo, "-c", "user.name=Test", "-c", "user.email=test@example.com", *, out: File::NULL, err: File::NULL)

  def write(path, body = "x\n")
    FileUtils.mkdir_p(File.dirname(File.join(repo, path)))
    File.write(File.join(repo, path), body)
  end

  before do
    git("init", "-q")
    write("README.md")
    git("add", "-A")
    git("commit", "-qm", "base")
    git("branch", "base")
    write("lib/openlanes/x.rb")
    git("add", "-A")
    git("commit", "-qm", "work")
  end

  after { FileUtils.rm_rf(repo) }

  it "lists the files the branch changes since its base" do
    expect(changes.call(subject_double)).to eq(["lib/openlanes/x.rb"])
  end

  it "answers nil when the base cannot be found" do
    expect(described_class.new(worktree:, base: ->(_) { "nowhere" }).call(subject_double)).to be_nil
  end

  it "answers nil when the plan has no checkout" do
    FileUtils.rm_rf(repo)
    expect(changes.call(subject_double)).to be_nil
  end
end
