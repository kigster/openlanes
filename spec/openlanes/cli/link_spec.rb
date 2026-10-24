# frozen_string_literal: true

require "open3"

# The integration check: the real binary, a real git repository, nothing
# stubbed. The guards are facts about git's layout, and the candidate list is
# a fact about the specs on disk, so a double of either would only agree with
# itself.
RSpec.describe "openlanes link" do
  let(:exe) { File.expand_path("../../../exe/openlanes", __dir__) }
  let(:tmp) { File.realpath(Dir.mktmpdir("link")) }
  let(:repo) { File.join(tmp, "project") }

  def git(*) = system("git", "-C", repo, *, out: File::NULL, err: File::NULL)

  after { FileUtils.rm_rf(tmp) }

  before do
    plans = PlansFixture::Builder.new(File.join(repo, OpenLanes::PLANS_DIR))
    plans.plan "050.00",
      :ready_for_linking,
      "parser-consumer",
      files: { "spec.md" => "---\nlane: full\n---\n# Parser Consumer\n\nCalls the parser plan 034 builds.\n",
               "plan.md" => "" }
    plans.plan "051.00",
      :ready_for_planning,
      "readme-badge",
      files: { "spec.md" => "---\nlane: full\ndepends_on: [none]\n---\n# README Badge\n" }
    git("init", "-q", "--initial-branch=main")
    git("add", "-A")
    git("-c", "user.name=Example Dev", "-c", "user.email=dev@example.test", "commit", "-qm", "plans")
  end

  def link(dir, *) = Open3.capture3({ "NO_COLOR" => "1" }, exe, "link", *, chdir: dir)

  it "previews ewoki for the keyless plan only" do
    out, err, status = link(repo, "--dry-run")

    expect(status).to be_success, err
    expect(out).to include("would invoke ewoki-linker for 050.00")
    expect(out).not_to include("051.00")
  end

  it "warns inside a linked worktree, and goes on" do
    linked = File.join(tmp, "linked")
    git("worktree", "add", "-q", "-b", "feature", linked)

    out, err, status = link(linked, "--dry-run")

    expect(status).to be_success, err
    expect(out).to include("would invoke ewoki-linker for 050.00")
    expect(err).to include("linked worktree")
  end

  it "warns on a branch other than main, and goes on" do
    git("checkout", "-q", "-b", "feature")

    out, err, status = link(repo, "--dry-run")

    expect(status).to be_success, err
    expect(out).to include("would invoke")
    expect(err).to include("on branch feature, not main")
  end
end
