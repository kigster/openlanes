# frozen_string_literal: true

# What `worktree prune` asks and how it reports the answers. Whether a
# checkout's work landed is Vcs::Worktree#retire's to decide, against real
# repositories in its own spec; here GitHub, the worktrees and alock are
# doubles, and the property under test is that every checkout gets a row
# saying what happened to it and why.
RSpec.describe OpenLanes::CLI::WorktreePrune, :tree do
  subject(:command) { described_class.new }

  let(:worktree) { instance_double(OpenLanes::Vcs::Worktree, root: File.dirname(plans_root), dir: "/w", repository?: true, list: paths) }
  let(:github) { instance_double(OpenLanes::Vcs::GitHub) }
  let(:locks) { instance_double(OpenLanes::Engine::AgentLocks, held_in: nil) }
  let(:paths) { [] }
  let(:branches) { {} }

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(dir: plans_root, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  def retirement(path, removed:, reason:)
    OpenLanes::Vcs::Worktree::Retirement.new(path:, branch: branches[path], sha: "abcdef1234567890", removed:, reason:)
  end

  before do
    plans { |t| t.plan("001.00", :new, "anything", files: { "spec.md" => spec_body }) }
    allow(OpenLanes::Vcs).to receive_messages(worktree:, github:)
    allow(OpenLanes::Engine).to receive(:agent_locks).and_return(locks)
    allow(worktree).to receive(:branch_of) { |path| branches.fetch(path, "") }
  end

  it "says so when there are no plan worktrees" do
    _out, err, status = run

    aggregate_failures do
      expect(status).to eq(0)
      expect(err).to include("No plan worktrees under /w.")
    end
  end

  it "refuses outside a git repository" do
    allow(worktree).to receive(:repository?).and_return(false)

    expect(run.last).to eq(66)
  end

  context "with a checkout of each kind" do
    let(:paths) { %w[/w/001.00-landed /w/002.00-unmerged /w/003.00-open /w/004.00-detached /w/005.00-broken] }
    let(:branches) do
      { "/w/001.00-landed" => "kig/001.00-landed", "/w/002.00-unmerged" => "kig/002.00-unmerged",
        "/w/003.00-open" => "kig/003.00-open", "/w/005.00-broken" => "kig/005.00-broken" }
    end

    before do
      allow(github).to receive(:merged_pull_for) do |branch|
        case branch
        when "kig/001.00-landed" then { number: 11, base: "main", merge_commit: "m1" }
        when "kig/002.00-unmerged" then { number: 12, base: "main", merge_commit: "m2" }
        when "kig/005.00-broken" then raise OpenLanes::Error, "gh is down"
        end
      end
      allow(worktree).to receive(:retire) do |path, dry_run:, **|
        if path.end_with?("landed")
          dry_run ? retirement(path, removed: false, reason: "would be removed: landed in m1") : retirement(path, removed: true, reason: "landed in m1")
        else
          retirement(path, removed: false, reason: "its branch has work that is not in m2")
        end
      end
    end

    it "gives every checkout a row saying what happened to it and why" do
      out, = run

      aggregate_failures do
        expect(out.lines.first).to match(/\AWORKTREE\s+BRANCH\s+PR\s+RESULT\n\z/)
        expect(out).to match(%r{001\.00-landed\s+kig/001\.00-landed\s+#11\s+removed \(abcdef12\): landed in m1})
        expect(out).to match(%r{002\.00-unmerged\s+kig/002\.00-unmerged\s+#12\s+kept: its branch has work that is not in m2})
        expect(out).to match(%r{003\.00-open\s+kig/003\.00-open\s+kept: no merged pull request})
        expect(out).to match(/004\.00-detached\s+\(detached\)\s+kept: detached HEAD/)
        expect(out).to match(%r{005\.00-broken\s+kig/005\.00-broken\s+kept: gh is down})
      end
    end

    it "asks alock about each checkout it would retire" do
      allow(locks).to receive(:held_in).with("/w/001.00-landed").and_return("backend-coder (fixing)")
      run

      expect(worktree).to have_received(:retire).with("/w/001.00-landed", merge_commit: "m1", base: "main", held: anything, dry_run: false) { |*, held:, **|
        expect(held.call("/w/001.00-landed")).to eq("backend-coder (fixing)")
      }
    end

    it "removes nothing on a dry run, and counts what it would remove" do
      out, err, = run(dry_run: true)

      aggregate_failures do
        expect(worktree).to have_received(:retire).with("/w/001.00-landed", merge_commit: "m1", base: "main", held: anything, dry_run: true)
        expect(out).to match(%r{001\.00-landed\s+kig/001\.00-landed\s+#11\s+would be removed: landed in m1})
        expect(unwrapped(err)).to include("1 removal pending")
      end
    end

    it "prints nothing when quiet" do
      expect(run(quiet: true).first).to eq("")
    end
  end
end
