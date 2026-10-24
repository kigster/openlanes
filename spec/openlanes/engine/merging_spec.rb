# frozen_string_literal: true

# The real GitHub seam, answered by the fake `gh`, over a real `.plans`
# tree: what is under test is which labels, merges and rebases reach GitHub,
# and where the folder ends up.
RSpec.describe OpenLanes::Engine::Merging, :fake_gh, :tree do
  subject(:merging) do
    described_class.new(github: OpenLanes::Vcs::GitHub.new,
      outcomes: OpenLanes::Engine::PrOutcomes.new(tree_dir: plans_root, agents: OpenLanes::Agents::Registry.new),
      merge_by: -> { merge_by },
      clock: -> { now })
  end

  let(:merge_by) { :auto }
  let(:now) { Time.now }
  let(:green) { [{ "name" => "ci", "state" => "SUCCESS", "bucket" => "pass" }] }
  let(:numbers) { [1] }

  def plan = OpenLanes::Plans::Tree.new(dir: plans_root).find("033.00")
  def labels(number = 1) = gh.dig("prs", number.to_s, "labels")
  def merges = gh_calls.select { it.take(2) == %w[pr merge] }.map { it[2].to_i }
  def rebases = gh_calls.select { it.take(2) == %w[pr update-branch] }.map { it[2].to_i }
  def risk = OpenLanes::Plans::PlanState.for(plan.feature.path).merge_risk

  before do
    plans do |t|
      t.plan "033.00",
        :completed,
        "merge-risk",
        files: { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## U1\n" },
        prs:   numbers.map { t.open(it, "Part #{it}") }
    end
    edit_gh do |state|
      state["labels"] = %w[ready-to-merge]
      state["prs"] = numbers.to_h do |n|
        [n.to_s, gh_pr(title: "Part #{n}", url: "https://github.com/example/repo/pull/#{n}", labels: %w[ready-to-merge], checks: green)]
      end
    end
  end

  describe ".verdicts" do
    it "reads one verdict per pull request, a bare one for the rest, and manual for anything unsaid" do
      aggregate_failures do
        expect(described_class.verdicts("auto #12, manual #13", [12, 13, 14])).to eq(12 => "auto", 13 => "manual", 14 => "manual")
        expect(described_class.verdicts("Auto", [1, 2])).to eq(1 => "auto", 2 => "auto")
        expect(described_class.verdicts("auto, manual #2", [1, 2])).to eq(1 => "auto", 2 => "manual")
        expect(described_class.verdicts(nil, [1])).to eq(1 => "manual")
        expect(described_class.verdicts("looks fine to me", [1])).to eq(1 => "manual")
      end
    end

    it "reads anything but a bare verdict list as manual for every pull request" do
      aggregate_failures do
        expect(described_class.verdicts("Do not auto-merge; drops a column.", [1, 2])).to eq(1 => "manual", 2 => "manual")
        expect(described_class.verdicts("Risky: do not auto-merge #13. manual", [13])).to eq(13 => "manual")
        expect(described_class.verdicts("manual #2; auto", [1, 2])).to eq(1 => "manual", 2 => "manual")
        expect(described_class.verdicts("auto #1, manual", [1, 2])).to eq(1 => "manual", 2 => "manual")
      end
    end
  end

  describe "#assessed?" do
    it "is false until palpatine rules, and false again once the plan has moved since" do
      before = merging.assessed?(plan)
      OpenLanes::Plans::PlanState.for(plan.feature.path).assess!({ 1 => "manual" })
      after = merging.assessed?(plan)
      OpenLanes::Plans::PlanState.for(plan.feature.path).update { it["moves"] = it["moves"].to_i + 1 }

      aggregate_failures do
        expect(before).to be(false)
        expect(after).to be(true)
        expect(merging.assessed?(plan)).to be(false)
      end
    end
  end

  describe "#advance" do
    it "does nothing before palpatine has ruled" do
      expect(merging.advance(plan).note).to eq("palpatine has not ruled yet")
    end
  end

  context "when palpatine says manual" do
    it "labels the pull request merge-manually, merges nothing, and leaves the plan at 🏁" do
      result = merging.assess(plan, "manual")

      aggregate_failures do
        expect(result.note).to eq("PR #1 merge-manually: palpatine said manual")
        expect(labels).to eq(%w[merge-manually])
        expect(merges).to be_empty
        expect(plan.status.key).to eq(:completed)
        expect(risk["verdicts"]).to eq("1" => "manual")
      end
    end

    it "does not label it twice on the next poll" do
      merging.assess(plan, "manual")
      calls = gh_calls.size
      merging.advance(plan)

      expect(gh_calls.drop(calls).map { it.take(2) }).to eq([%w[pr view]])
    end

    it "takes the plan to ✅ once a person merges it" do
      merging.assess(plan, "manual")
      edit_gh { it["prs"]["1"].merge!("state" => "MERGED", "merged_at" => "2026-10-20T12:00:00Z") }
      result = merging.advance(plan)

      aggregate_failures do
        expect(result.to).to eq(:approved)
        expect(OpenLanes::Plans::Tree.new(dir: plans_root).find("033.00").status.key).to eq(:approved)
      end
    end
  end

  context "when palpatine says auto but merge.by is human" do
    let(:merge_by) { :human }

    it "leaves the pull request for a person all the same" do
      result = merging.assess(plan, "auto")

      aggregate_failures do
        expect(result.note).to eq("PR #1 merge-manually: merge.by is human")
        expect(labels).to eq(%w[merge-manually])
        expect(merges).to be_empty
      end
    end
  end

  context "when palpatine says auto under merge.by: auto" do
    it "merges the only pull request, labels it auto-merged, and takes the plan to ✅" do
      result = merging.assess(plan, "auto")
      settled = OpenLanes::Plans::Tree.new(dir: plans_root).find("033.00")

      aggregate_failures do
        expect(result).to have_attributes(to: :approved, merged: true)
        expect(merges).to eq([1])
        expect(labels).to eq(%w[auto-merged])
        expect(settled.status.key).to eq(:approved)
        expect(settled.pull_requests.first).to be_merged
      end
    end

    it "waits while CI is still running" do
      edit_gh { it["prs"]["1"]["checks"] = [{ "name" => "ci", "state" => "PENDING", "bucket" => "pending" }] }

      aggregate_failures do
        expect(merging.assess(plan, "auto").note).to eq("PR #1 waits on CI before it merges")
        expect(merges).to be_empty
        expect(labels).to eq(%w[ready-to-merge])
      end
    end

    it "leaves for a person a pull request no CI ran on" do
      edit_gh { it["prs"]["1"]["checks"] = [] }
      result = merging.assess(plan, "auto")

      aggregate_failures do
        expect(result.note).to eq("PR #1 merge-manually: no CI checks ran")
        expect(merges).to be_empty
        expect(labels).to eq(%w[merge-manually])
      end
    end

    it "merges only the head CI was read for, and leaves a moved branch for a person" do
      edit_gh { it["prs"]["1"]["head"] = "moved" }
      github = OpenLanes::Vcs::GitHub.new
      allow(github).to(receive(:pull_request).and_wrap_original { |m, *a| m.call(*a).merge(head: "c0ffee1") })
      mover = described_class.new(github:,
        outcomes: OpenLanes::Engine::PrOutcomes.new(tree_dir: plans_root, agents: OpenLanes::Agents::Registry.new),
        merge_by: :auto)
      result = mover.assess(plan, "auto")

      aggregate_failures do
        expect(gh_calls.find { it.take(2) == %w[pr merge] }).to include("--match-head-commit", "c0ffee1")
        expect(result.note).to start_with("PR #1 merge-manually: could not merge #1: Head branch was modified")
        expect(labels).to eq(%w[merge-manually])
      end
    end

    it "logs a note it cannot read, and merges nothing" do
      allow(OpenLanes::UI).to receive(:log)
      merging.assess(plan, "Do not auto-merge; drops a column.")

      aggregate_failures do
        expect(OpenLanes::UI).to have_received(:log).with(/not a verdict list.*Do not auto-merge/, hash_including(level: :warn))
        expect(merges).to be_empty
        expect(labels).to eq(%w[merge-manually])
      end
    end

    it "leaves for a person a pull request GitHub refuses to merge" do
      edit_gh { it["prs"]["1"]["unmergeable"] = "the base branch policy prohibits the merge" }
      result = merging.assess(plan, "auto")

      aggregate_failures do
        expect(result.note).to start_with("PR #1 merge-manually: could not merge #1")
        expect(labels).to eq(%w[merge-manually])
        expect(plan.status.key).to eq(:completed)
      end
    end

    # U3: the conflict sweep hands it to bb8-resolver, and the verdict stays.
    it "waits on a pull request that does not merge clean, rather than leaving it for a person" do
      edit_gh { it["prs"]["1"]["merge_state"] = "DIRTY" }
      result = merging.assess(plan, "auto")

      aggregate_failures do
        expect(result.note).to eq("PR #1 waits on its conflicts with main being resolved")
        expect(merges).to be_empty
        expect(labels).to eq(%w[ready-to-merge])
      end
    end

    it "waits while GitHub has not worked out whether it merges clean" do
      edit_gh { it["prs"]["1"]["merge_state"] = "UNKNOWN" }

      aggregate_failures do
        expect(merging.assess(plan, "auto").note).to include("waits on GitHub")
        expect(merges).to be_empty
        expect(labels).to eq(%w[ready-to-merge])
      end
    end

    it "holds the merge while CI on main is red, pending or missing" do
      runs = { "red"     => [{ "name" => "ci", "status" => "completed", "conclusion" => "failure" }],
               "pending" => [{ "name" => "ci", "status" => "in_progress", "conclusion" => nil }],
               "none"    => [] }
      notes = runs.map do |_, checks|
        edit_gh { it["main_checks"] = checks }
        merging.assess(plan, "auto").note
      end

      aggregate_failures do
        expect(notes).to eq(["PR #1 waits on CI on main, which is red", "PR #1 waits on CI on main, which is pending",
                             "PR #1 waits on CI on main, which is none"])
        expect(merges).to be_empty
        expect(labels).to eq(%w[ready-to-merge])
      end
    end

    it "merges when CI on main reports commit statuses only, as CircleCI does" do
      edit_gh do |gh|
        gh["main_checks"] = []
        gh["main_statuses"] = [{ "context" => "ci/circleci: test", "state" => "success" }]
      end

      expect(merging.assess(plan, "auto")).to have_attributes(to: :approved, merged: true)
    end

    it "holds the merge on a red status on main beside a green check run" do
      edit_gh { it["main_statuses"] = [{ "context" => "ci/circleci: test", "state" => "failure" }] }

      aggregate_failures do
        expect(merging.assess(plan, "auto").note).to eq("PR #1 waits on CI on main, which is red")
        expect(merges).to be_empty
      end
    end

    # U4: the conflict sweep rebases it on GitHub, and CI runs on the new head.
    it "waits on a pull request whose branch is behind main" do
      edit_gh { it["prs"]["1"]["merge_state"] = "BEHIND" }
      result = merging.assess(plan, "auto")

      aggregate_failures do
        expect(result.note).to eq("PR #1 waits on its branch being rebased onto main")
        expect(merges).to be_empty
        expect(labels).to eq(%w[ready-to-merge])
      end
    end

    context "with a sibling" do
      let(:numbers) { [1, 2] }

      it "merges one, rebases the other onto main, and merges it once CI is green on its new head" do
        first = merging.assess(plan, "auto")
        rebased = risk["rebased"].keys
        waiting = merging.advance(plan)
        edit_gh { it["prs"]["2"]["checks"] = green }
        last = merging.advance(plan)

        aggregate_failures do
          expect(first).to have_attributes(merged: true, to: nil)
          expect(rebases).to eq([2])
          expect(rebased).to eq(["2"])
          expect(waiting.note).to eq("PR #2 waits on CI before it merges")
          expect(last).to have_attributes(merged: true, to: :approved)
          expect(merges).to eq([1, 2])
          expect([labels(1), labels(2)]).to eq([%w[auto-merged], %w[auto-merged]])
        end
      end

      it "sends the plan to 🔴, with the reason, when the sibling no longer rebases onto main" do
        edit_gh { it["prs"]["2"]["conflicts"] = true }
        result = merging.assess(plan, "auto")
        rejected = OpenLanes::Plans::Tree.new(dir: plans_root).find("033.00")
        mail = OpenLanes::Plans::Mailbox.new(dir: rejected.feature.path).messages

        aggregate_failures do
          expect(result.to).to eq(:rejected)
          expect(result.note).to include("PR #2 back to the builders", "no longer rebases onto main")
          expect(labels(1)).to eq(%w[auto-merged])
          expect(labels(2)).to eq(%w[review-rejected])
          expect(gh.dig("prs", "2", "comments").map { it["body"] }.join).to include("Cannot update PR branch due to conflicts")
          expect(rejected.status.key).to eq(:rejected)
          expect(mail.map(&:to)).to include("luke-backend", "rey-frontend")
        end
      end

      it "rules on each pull request by its own verdict" do
        merging.assess(plan, "auto #1, manual #2")

        aggregate_failures do
          expect(merges).to eq([1])
          expect(labels(2)).to eq(%w[ready-to-merge])
          merging.advance(OpenLanes::Plans::Tree.new(dir: plans_root).find("033.00"))
          expect(labels(2)).to eq(%w[merge-manually])
        end
      end
    end
  end

  context "when the plan's own checkout builds the sibling" do
    subject(:merging) do
      described_class.new(github: OpenLanes::Vcs::GitHub.new,
        outcomes:  OpenLanes::Engine::PrOutcomes.new(tree_dir: plans_root, agents: OpenLanes::Agents::Registry.new),
        merge_by:  :auto,
        worktree:,
        publisher:)
    end

    let(:numbers) { [1, 2] }
    let(:own) { Dir.mktmpdir("openlanes-own-checkout") }
    let(:checkout) { OpenLanes::Vcs::Worktree::Checkout.new(ordinal: "033.00", branch: "kig/033", path: own, created: false) }
    let(:worktree) { instance_double(OpenLanes::Vcs::Worktree, path_for: own, checkout_for: checkout) }
    let(:publisher) { instance_double(OpenLanes::Vcs::Publisher, branch_mismatch: nil, pushed!: nil) }
    let(:refresh) { instance_double(OpenLanes::Vcs::Refresh, abort!: nil) }

    def outcome(kind, **) = OpenLanes::Vcs::Refresh::Outcome.new(kind:, **)

    before { allow(OpenLanes::Vcs::Refresh).to receive(:new).with(path: own).and_return(refresh) }

    after { FileUtils.rm_rf(own) }

    it "rebases it locally and pushes it with the lease, not through GitHub" do
      allow(refresh).to receive(:call).and_return(outcome(:rebased, base: "origin/main"))
      merging.assess(plan, "auto")

      aggregate_failures do
        expect(publisher).to have_received(:pushed!).with(checkout, "HEAD").once
        expect(rebases).to be_empty
      end
    end

    it "sends the plan to 🔴 naming the files when the local rebase conflicts" do
      allow(refresh).to receive(:call).and_return(outcome(:conflicted, base: "origin/main", files: %w[lib/a.rb]))
      result = merging.assess(plan, "auto")

      aggregate_failures do
        expect(refresh).to have_received(:abort!).with("conflicts after a sibling merged")
        expect(result.note).to include("PR #2 no longer rebases onto origin/main: conflicts in lib/a.rb.")
        expect(result.to).to eq(:rejected)
      end
    end

    it "lets GitHub rebase it when the local tree refuses" do
      allow(refresh).to receive(:call).and_return(outcome(:skipped, reason: "dirty tree"))
      merging.assess(plan, "auto")

      expect(rebases).to eq([2])
    end

    it "lets GitHub rebase a sibling built from another branch" do
      allow(publisher).to receive(:branch_mismatch).and_return("PR #2 is built from kig/other")
      merging.assess(plan, "auto")

      expect(rebases).to eq([2])
    end

    it "leaves the sibling for a person when its rebase raises, and the next pass does not merge it" do
      allow(refresh).to receive(:call).and_return(outcome(:rebased, base: "origin/main"))
      allow(publisher).to receive(:pushed!).and_raise(OpenLanes::Error, "lease refused")
      allow(OpenLanes::UI).to receive(:log)
      first = merging.assess(plan, "auto")
      later = merging.advance(plan)

      aggregate_failures do
        expect(first).to have_attributes(merged: true)
        expect(first.note).to include("PR #2 merge-manually: rebase onto main failed: lease refused")
        expect(OpenLanes::UI).to have_received(:log).with(/rebase after merging #1 not finished: lease refused/, hash_including(level: :warn))
        expect(labels(2)).to eq(%w[merge-manually])
        expect(gh.dig("prs", "2", "comments").map { it["body"] }).to include("rebase onto main failed: lease refused")
        expect(merges).to eq([1])
        expect(later.note).not_to include("auto-merged")
        expect(merges).to eq([1])
        expect(labels(2)).to eq(%w[merge-manually])
      end
    end

    context "with two siblings still open" do
      let(:numbers) { [1, 2, 3] }

      it "leaves the later sibling too when an earlier rebase raises, and the next pass merges neither" do
        allow(refresh).to receive(:call).and_return(outcome(:rebased, base: "origin/main"))
        allow(publisher).to receive(:pushed!).and_raise(OpenLanes::Error, "lease refused")
        merging.assess(plan, "auto")
        merging.advance(plan)

        aggregate_failures do
          expect(labels(2)).to eq(%w[merge-manually])
          expect(labels(3)).to eq(%w[merge-manually])
          expect(merges).to eq([1])
        end
      end
    end
  end

  context "when another plan has a checkout" do
    subject(:merging) do
      described_class.new(github: OpenLanes::Vcs::GitHub.new,
        outcomes:  OpenLanes::Engine::PrOutcomes.new(tree_dir: plans_root, agents: OpenLanes::Agents::Registry.new),
        merge_by:  :auto,
        worktree:,
        publisher:)
    end

    let(:other) { Dir.mktmpdir("openlanes-other-checkout") }
    let(:missing) { File.join(other, "never-made") }
    let(:checkout) { OpenLanes::Vcs::Worktree::Checkout.new(ordinal: "034.00", branch: "kig/034", path: other, created: false) }
    # The merged plan has no checkout of its own here, so nothing to retire.
    let(:worktree) { instance_double(OpenLanes::Vcs::Worktree, checkout_for: checkout, checkouts_of: []) }
    let(:publisher) { instance_double(OpenLanes::Vcs::Publisher, branch_mismatch: nil, pushed!: nil) }
    let(:refresh) { instance_double(OpenLanes::Vcs::Refresh, abort!: nil) }

    def outcome(kind, **) = OpenLanes::Vcs::Refresh::Outcome.new(kind:, **)

    before do
      plans { |t| t.plan "034.00", :building, "other-work", prs: [t.open(9, "Other")] }
      allow(worktree).to receive(:path_for) { |feature| feature.ordinal.to_s == "034.00" ? other : missing }
      allow(OpenLanes::Vcs::Refresh).to receive(:new).with(path: other).and_return(refresh)
      allow(refresh).to receive(:call).and_return(outcome(:rebased, base: "origin/main"))
    end

    after { FileUtils.rm_rf(other) }

    it "queues its rebase after a merge and never moves it from inside the merge" do
      merging.assess(plan, "auto")

      aggregate_failures do
        expect(merges).to eq([1])
        expect(merging.pending_rebases).to eq(%w[034.00])
        expect(refresh).not_to have_received(:call)
      end
    end

    it "keeps the rebase queued while an agent runs in that checkout, leaving its HEAD alone" do
      merging.assess(plan, "auto")

      aggregate_failures do
        expect(merging.rebase_queued(busy: %w[034.00])).to be_empty
        expect(refresh).not_to have_received(:call)
        expect(merging.pending_rebases).to eq(%w[034.00])
      end
    end

    it "rebases and pushes it once the checkout is idle" do
      merging.assess(plan, "auto")

      aggregate_failures do
        expect(merging.rebase_queued(busy: [])).to eq(["034.00 rebased onto main"])
        expect(publisher).to have_received(:pushed!).with(checkout, "HEAD").once
        expect(merging.pending_rebases).to be_empty
      end
    end

    it "leaves a checkout with uncommitted work untouched and unpushed" do
      allow(refresh).to receive(:call).and_return(outcome(:skipped, reason: "uncommitted changes in the worktree"))
      merging.assess(plan, "auto")

      aggregate_failures do
        expect(merging.rebase_queued(busy: [])).to eq(["034.00 not rebased: uncommitted changes in the worktree"])
        expect(publisher).not_to have_received(:pushed!)
      end
    end

    it "aborts a conflicting rebase and leaves it to that plan's next round" do
      allow(refresh).to receive(:call).and_return(outcome(:conflicted, base: "origin/main", files: %w[lib/a.rb]))
      merging.assess(plan, "auto")

      aggregate_failures do
        expect(merging.rebase_queued(busy: []).first).to include("conflicts with main in lib/a.rb")
        expect(refresh).to have_received(:abort!).with("conflicts after a merge to main")
        expect(publisher).not_to have_received(:pushed!)
      end
    end

    it "queues nothing when the merge does not happen" do
      edit_gh { it["main_checks"] = [] }
      merging.assess(plan, "auto")

      expect(merging.pending_rebases).to be_empty
    end
  end

  # Whether a checkout's work landed is Vcs::Worktree's question, asked of
  # real repositories in its own spec. Here: whether, when, and with what.
  describe "retiring the plan's worktree" do
    subject(:merging) do
      described_class.new(github: OpenLanes::Vcs::GitHub.new,
        outcomes: OpenLanes::Engine::PrOutcomes.new(tree_dir: plans_root, agents: OpenLanes::Agents::Registry.new),
        merge_by: -> { merge_by },
        worktree:,
        clock:    -> { now },
        held:)
    end

    let(:worktree) { instance_double(OpenLanes::Vcs::Worktree, checkouts_of: ["/w/033.00-merge-risk"]) }
    let(:held) { ->(_path) {} }
    let(:retired) do
      OpenLanes::Vcs::Worktree::Retirement.new(path: "/w/033.00-merge-risk",
        branch: "kig/033.00-merge-risk",
        sha: "a" * 40,
        removed: true,
        reason: "landed in 5feedfac")
    end

    before { allow(worktree).to receive(:retire).and_return(retired) }

    it "retires it once a person merges the plan's pull request" do
      merging.assess(plan, "manual")
      edit_gh { it["prs"]["1"].merge!("state" => "MERGED", "merged_at" => "2026-10-20T12:00:00Z", "merge_commit" => "c0mm1t") }
      merging.advance(plan)

      expect(worktree).to have_received(:retire).with("/w/033.00-merge-risk", merge_commit: "c0mm1t", base: "main", held:)
    end

    it "retires it once the engine merges it, with the commit GitHub merged it as" do
      merging.assess(plan, "auto")

      expect(worktree).to have_received(:retire).with("/w/033.00-merge-risk", merge_commit: "5feedface1", base: "main", held:)
    end

    it "leaves it alone when the pull request was closed unmerged" do
      merging.assess(plan, "manual")
      edit_gh { it["prs"]["1"]["state"] = "CLOSED" }
      merging.advance(plan)

      expect(worktree).not_to have_received(:retire)
    end

    it "logs a retirement GitHub could not answer for, and carries on" do
      allow(worktree).to receive(:retire).and_raise(OpenLanes::Error, "boom")
      allow(OpenLanes::UI).to receive(:log)

      expect(merging.assess(plan, "auto")).to have_attributes(merged: true)
      expect(OpenLanes::UI).to have_received(:log).with("worktree not retired: boom", level: :warn, plan: "033.00")
    end

    context "with a second pull request still open" do
      let(:numbers) { [1, 2] }

      # The sibling is rebased in that very checkout after the merge.
      it "keeps the checkout" do
        allow(OpenLanes::Vcs::Refresh).to receive(:new).and_return(instance_double(OpenLanes::Vcs::Refresh,
          call: OpenLanes::Vcs::Refresh::Outcome.new(kind: :current)))
        allow(worktree).to receive_messages(path_for: "/w/033.00-merge-risk", checkout_for: nil)
        merging.assess(plan, "auto")

        expect(worktree).not_to have_received(:retire)
      end
    end
  end
end
