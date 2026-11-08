# frozen_string_literal: true

# The watch beside Merging (#171), with nothing between them mocked: the
# real `Vcs::GitHub` answered by the fake `gh`, the real {PrWatch},
# {PrOutcomes}, {Merging}, {Finishes} and both steps, over a real `.plans`
# tree. Only the dispatcher is left out, as the callables its steps share.
RSpec.describe OpenLanes::Engine::Steps::Watch, :fake_gh, :tree do
  let(:github) { OpenLanes::Vcs::GitHub.new }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:outcomes) { OpenLanes::Engine::PrOutcomes.new(tree_dir: plans_root, agents: OpenLanes::Agents::Registry.new) }
  let(:merging) { OpenLanes::Engine::Merging.new(github:, outcomes:, merge_by: :auto) }
  # researcher handles only ⚪, so nothing here would start an agent.
  let(:runner) do
    OpenLanes::Engine::Runner.new(tree:,
      executor: ->(*) { raise "no agent should start" },
      agents:   OpenLanes::Agents::Registry.new.only("researcher"),
      merging:,
      sleeper:  ->(_) {})
  end
  let(:finishes) { OpenLanes::Engine::Finishes.new(runner:, clock: Time) }
  let(:woken) { [] }
  let(:context) do
    OpenLanes::Engine::Steps::Context.new(runner:, busy: -> { [] }, wake: -> { woken << true }, reopen: ->(_) {})
  end
  let(:step) { described_class.new(context, watch: OpenLanes::Engine::PrWatch.new(github:, interval: 0), finishes:, state: nil) }
  let(:merges) { OpenLanes::Engine::Steps::Merges.new(context) }
  let(:url) { "https://github.com/example/repo/pull/1" }

  def plan = tree.everything.reload.find("033.00")
  def log_lines = @log_lines ||= []

  before do
    plans do |t|
      t.plan "033.00", :completed, "merge-risk", files: { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## U1\n" }, prs: [t.open(1, "Part 1")]
    end
    OpenLanes::Plans::PlanState.for(plan.feature.path).assess!({ 1 => verdict })
    edit_gh do |state|
      state["labels"] = OpenLanes::Plans::ReviewLabel::ALL.map(&:name)
      state["prs"] = { "1" => gh_pr(title: "Part 1", url:, labels: [], checks: []).merge(pull) }
    end
    allow(OpenLanes::UI).to receive(:log) { |line, **| log_lines << line }
  end

  # A person merges at 🏁 while the watch's poll is out. The poll read the
  # row as `Open`, Merging then reads the merge and moves the plan to ✅,
  # and only after that does the watch's stale answer arrive.
  context "when Merging settles a merge the watch's poll is still carrying" do
    let(:verdict) { "manual" }
    let(:pull) { { "state" => "MERGED", "merged_at" => "2026-10-20T12:00:00Z" } }

    before do
      step.call
      step.join
      merges.call
    end

    it "lets Merging record the merge, and moves the plan to ✅" do
      aggregate_failures do
        expect(plan.status.key).to eq(:approved)
        expect(plan.pull_requests.first.merged?).to be(true)
        expect(log_lines).to include("PR #1 merged")
        expect(woken.size).to eq(1)
      end
    end

    it "drops the stale answer: no second log line, no finish kept, no wakeup" do
      step.call

      aggregate_failures do
        expect(log_lines).not_to include(a_string_starting_with("033.00: PR #1 merged"))
        expect(log_lines.count("PR #1 merged")).to eq(1)
        expect(finishes.ordinals).not_to include("033.00")
        expect(woken.size).to eq(1)
        expect(plan.status.key).to eq(:approved)
      end
    end
  end

  # Under `merge.by: auto` the engine would merge this pull request itself,
  # but a person labelled it `review-rejected` first. Before #171 nothing
  # watched in auto mode, and the label went unread.
  context "when a person rejects an auto-merge pull request on GitHub" do
    let(:verdict) { "auto" }
    let(:pull) do
      { "labels"   => [OpenLanes::Plans::ReviewLabel::REJECTED.name],
        "comments" => [{ "author" => { "login" => "octo" }, "body" => "Rename the method", "url" => "#{url}#c1" }] }
    end
    let(:mail) { OpenLanes::Plans::Mailbox.new(dir: plan.feature.path).messages }

    before do
      merges.call
      step.call
      step.join
      step.call
    end

    it "sends the plan from 🏁 to 🔴 and mails the comments to the builders" do
      aggregate_failures do
        expect(plan.status.key).to eq(:rejected)
        expect(mail.map(&:to)).to include("backend-coder", "frontend-coder")
        expect(mail.first.body).to include("Rename the method")
        expect(log_lines).to include(a_string_starting_with("033.00: PR #1 labelled review-rejected"))
        expect(woken.size).to eq(1)
      end
    end

    it "never merges it" do
      expect(gh_calls.select { it.take(2) == %w[pr merge] }).to be_empty
    end
  end
end
