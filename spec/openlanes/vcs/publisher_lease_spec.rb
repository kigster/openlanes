# frozen_string_literal: true

require "tty/command"

# A branch the harness rebased has to replace what origin holds, and must
# not replace anything somebody else pushed there. Real pushes, to a bare
# repository in a temp dir.
RSpec.describe OpenLanes::Vcs::Publisher, :origin do
  subject(:publisher) { described_class.new(root: main, command: TTY::Command.new(printer: :null), dry_run: false) }

  let(:tmp) { Dir.mktmpdir("openlanes-lease") }
  let(:main) { File.join(tmp, "project") }
  let(:upstream) { publish_with_origin(main, tmp) }
  let(:worktrees) { OpenLanes::Vcs::Worktree.new(root: main, dir: File.join(tmp, "project.worktrees"), user: "tester", seeder: nil) }
  let(:feature) do
    OpenLanes::Plans::Feature.new(ordinal: OpenLanes::Plans::Ordinal.parse("008.01"),
      status: OpenLanes::Plans::STATUS_BY_KEY.fetch(:building),
      slug: "ewoki-linker",
      dirname: "008.01-🟡--ewoki-linker",
      path: File.join(main, OpenLanes::PLANS_DIR, "008.01-🟡--ewoki-linker"))
  end
  let(:checkout) { worktrees.checkout_for(feature) }

  after { FileUtils.rm_rf(tmp) }

  before do
    upstream
    commit_file(checkout.path, "lib/plan.rb", "# plan\n")
    publisher.send(:push, checkout)
  end

  def remote_branch = git!(upstream, "ls-remote", "origin", "refs/heads/#{checkout.branch}").split.first

  it "pushes a branch with no tracking ref yet as a plain push" do
    expect(remote_branch).to eq(git!(checkout.path, "rev-parse", "HEAD"))
  end

  it "replaces the published branch after a rebase, under a lease" do
    land(upstream, "lib/other.rb", "# other\n")
    expect(OpenLanes::Vcs::Refresh.new(path: checkout.path).call.kind).to eq(:rebased)
    publisher.send(:push, checkout)

    expect(remote_branch).to eq(git!(checkout.path, "rev-parse", "HEAD"))
  end

  it "refuses when somebody else pushed to the branch since the last fetch" do
    git!(upstream, "fetch", "-q", "origin", checkout.branch)
    git!(upstream, "checkout", "-q", "-b", "theirs", "FETCH_HEAD")
    theirs = commit_file(upstream, "lib/theirs.rb", "# theirs\n")
    git!(upstream, "push", "-q", "origin", "theirs:#{checkout.branch}")
    git!(checkout.path, "commit", "-q", "--amend", "-m", "rewritten")

    aggregate_failures do
      expect { publisher.send(:push, checkout) }.to raise_error(TTY::Command::ExitError)
      expect(remote_branch).to eq(theirs)
    end
  end
end
