# frozen_string_literal: true

require "tmpdir"

RSpec.describe "PR and human-answer events", :tree do
  let(:log_dir) { Dir.mktmpdir("events") }
  let(:sink) { OpenLanes::Events::Sink.new(dir: log_dir, node: "n1", checkout: "c1", project: "demo", run: "r1") }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:lines) { File.exist?(sink.path) ? File.readlines(sink.path).map { JSON.parse(it) } : [] }
  let(:events) { OpenLanes::Events::Log.new(dir: log_dir).events }

  after { FileUtils.rm_rf(log_dir) }

  def files = { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## U1\n" }
  def outcome(plan, number, kind) = OpenLanes::Engine::PrWatch::Outcome.new(plan:, pr: number, kind:, comments: [])

  describe OpenLanes::Engine::PrOutcomes do
    let(:effects) { described_class.new(tree_dir: plans_root, agents: OpenLanes::Agents::Registry.new, events: sink) }

    it "records a merge once, however often the watch reports it" do
      plans { |t| t.plan "003.00", :in_review, "merged", files:, prs: [t.open(13, "c")] }
      2.times { effects.apply(outcome("003.00", 13, :merged)) }

      expect(lines.map { it["kind"] }).to eq(%w[pr_merged])
      expect(lines.first).to include("plan" => "003.00", "payload" => { "number" => 13 })
    end

    it "records a close once" do
      plans { |t| t.plan "004.00", :in_review, "closed", files:, prs: [t.open(14, "d")] }
      2.times { effects.apply(outcome("004.00", 14, :closed)) }

      expect(lines.map { it["kind"] }).to eq(%w[pr_closed])
    end

    it "records a rejection as a review, once" do
      plans { |t| t.plan "001.00", :in_review, "judged", files:, prs: [t.open(11, "a")] }
      2.times { effects.apply(outcome("001.00", 11, :rejected)) }

      expect(lines.map { [it["kind"], it["payload"]] }).to eq([["pr_reviewed", { "number" => 11, "verdict" => "rejected" }]])
    end

    # Regression: the event id once left the round out, so a PR rejected
    # again after a fix round was deduped into its first rejection.
    it "records a second rejection of the same PR after a fix round as a second review" do
      plans { |t| t.plan "001.00", :in_review, "judged", files:, prs: [t.open(11, "a")] }
      effects.apply(outcome("001.00", 11, :rejected))
      tree.find("001.00").machine.promote!(:ready_for_review)
      effects.apply(outcome("001.00", 11, :rejected))

      aggregate_failures do
        expect(lines.map { it["kind"] }).to eq(%w[pr_reviewed pr_reviewed])
        expect(events.map { it.kind.to_s }).to eq(%w[pr_reviewed pr_reviewed])
      end
    end

    it "dedupes the same merge seen by two runs" do
      plans { |t| t.plan "003.00", :in_review, "merged", files:, prs: [t.open(13, "c")] }
      described_class.new(tree_dir: plans_root, agents: OpenLanes::Agents::Registry.new, events: sink)
                     .apply(outcome("003.00", 13, :merged))
      sink.with(run: "r2").record(:pr_merged, plan: "003.00", seq: 13, once: true, number: 13)

      expect(lines.size).to eq(2)
      expect(events.size).to eq(1)
    end
  end

  describe OpenLanes::Vcs::Publisher do
    it "records the pull request it opened, by number" do
      plans { |t| t.plan "005.00", :ready_for_review, "shipped", files: }
      publisher = described_class.new(root: plans_root, events: sink)
      publisher.send(:opened, tree.find("005.00"), "https://github.com/o/r/pull/15")

      expect(lines.map { [it["kind"], it["plan"], it["payload"]] }).to eq([["pr_opened", "005.00", { "number" => 15 }]])
    end
  end

  describe OpenLanes::Lifecycle::Unblocker do
    let(:agent) { OpenLanes::Agents::Registry.new.find("unblocker") }
    let(:body) { "# Blocked\n\n## B1. Which vendor\n\n## A1. Ours, the secret vendor list\n\n## B2. Later\n" }

    def folding(*numbers)
      lambda do |_agent, subject, **|
        path = File.join(subject.feature.path, "blocked.md")
        kept = File.read(path).split(/^(?=\#\# )/).reject { |s| numbers.any? { |n| s.start_with?("## B#{n}", "## A#{n}") } }
        File.write(path, kept.join)
        [true, "completed"]
      end
    end

    it "records one human_answered per answered question drained, with no answer text" do
      plans { |t| t.plan("001.00", :blocked, "a-feature", files: { "spec.md" => spec_body, "blocked.md" => body }) }
      described_class.new(tree:, agent:, executor: folding(1), commit: true, events: sink).drain(tree.reload.find("001.00"))

      expect(lines.map { it["kind"] }).to eq(%w[human_answered])
      expect(lines.first["payload"].keys).to match_array(%w[block answered_at])
      expect(lines.first["payload"]["block"]).to eq("B1")
      expect(File.read(sink.path)).not_to include("vendor")
    end

    it "keeps a re-block's B1 answer apart from the first block's, across runs" do
      plans { |t| t.plan("001.00", :blocked, "a-feature", files: { "spec.md" => spec_body, "blocked.md" => body }) }
      described_class.new(tree:, agent:, executor: folding(1, 2), commit: true, events: sink)
                     .drain(tree.reload.find("001.00"))
      reblocked = "# Blocked\n\n## B1. Which region\n\n## A1. The one nearest\n"
      File.write(File.join(tree.reload.find("001.00").feature.path, "blocked.md"), reblocked)
      described_class.new(tree:, agent:, executor: folding(1), commit: true, events: sink.with(run: "r2"))
                     .drain(tree.reload.find("001.00"))

      expect(lines.map { it["payload"]["block"] }).to eq(%w[B1 B1])
      expect(events.size).to eq(2)
    end

    it "dedupes the same drain seen by two runs" do
      plans { |t| t.plan("001.00", :blocked, "a-feature", files: { "spec.md" => spec_body, "blocked.md" => body }) }
      [sink, sink.with(run: "r2")].each do |each|
        path = File.join(tree.reload.find("001.00").feature.path, "blocked.md")
        File.write(path, body)
        described_class.new(tree:, agent:, executor: folding(1), commit: true, events: each).drain(tree.reload.find("001.00"))
      end

      expect(lines.size).to eq(2)
      expect(events.size).to eq(1)
    end

    it "records nothing on a dry run" do
      plans { |t| t.plan("001.00", :blocked, "a-feature", files: { "spec.md" => spec_body, "blocked.md" => body }) }
      described_class.new(tree:, agent:, executor: folding(1), commit: false, events: sink).drain(tree.reload.find("001.00"))

      expect(lines).to be_empty
    end
  end
end
