# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::PrOutcomes, :tree do
  subject(:effects) { described_class.new(tree_dir: plans_root, agents: OpenLanes::Agents::Registry.new) }

  let(:comments) { [{ author: "octo", body: "Fix the nil check", url: "https://github.com/o/r/pull/11#c1" }] }

  def outcome(plan, number, kind, comments: []) = OpenLanes::Engine::PrWatch::Outcome.new(plan:, pr: number, kind:, comments:)
  def plan(ordinal) = OpenLanes::Plans::Tree.new(dir: plans_root).find(ordinal)
  def files = { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## U1\n" }

  describe "a pull request labelled review-rejected" do
    before { plans { |t| t.plan "001.00", :in_review, "judged", files:, prs: [t.open(11, "a")] } }

    let!(:applied) { effects.apply(outcome("001.00", 11, :rejected, comments:)) }

    it "moves the plan to 🔴 and mails the comments to every agent who handles 🔴" do
      mail = OpenLanes::Plans::Mailbox.new(dir: plan("001.00").feature.path).messages

      aggregate_failures do
        expect(plan("001.00").status.key).to eq(:rejected)
        expect(applied).to have_attributes(plan: "001.00", pr: 11, to: :rejected)
        expect(mail.map(&:to)).to include("luke-backend", "rey-frontend")
        expect(mail.map(&:from).uniq).to eq(["github"])
        expect(mail.first.body).to include("PR #11 was labelled review-rejected", "octo", "Fix the nil check")
      end
    end

    it "does nothing the second time, so a poll every 15 s mails once" do
      expect(effects.apply(outcome("001.00", 11, :rejected, comments:))).to be_nil
    end
  end

  it "takes a 🟢 plan a person rejected before hansolo did through 👀 to 🔴" do
    plans { |t| t.plan "002.00", :ready_for_review, "early", files:, prs: [t.open(12, "b")] }
    effects.apply(outcome("002.00", 12, :rejected))

    expect(plan("002.00").status.key).to eq(:rejected)
  end

  it "says so in the mail when the rejection carries no comment" do
    plans { |t| t.plan "002.00", :in_review, "silent", files:, prs: [t.open(12, "b")] }
    effects.apply(outcome("002.00", 12, :rejected))

    expect(OpenLanes::Plans::Mailbox.new(dir: plan("002.00").feature.path).messages.first.body).to include("No comment")
  end

  it "leaves a plan an agent is already rebuilding where it is" do
    plans { |t| t.plan "002.00", :building, "fixing", files:, prs: [t.open(12, "b")] }

    aggregate_failures do
      expect(effects.apply(outcome("002.00", 12, :rejected))).to be_nil
      expect(plan("002.00").status.key).to eq(:building)
    end
  end

  describe "a merged pull request" do
    it "records it as merged and moves the plan to ✅" do
      plans { |t| t.plan "003.00", :in_review, "merged", files:, prs: [t.open(13, "c")] }
      applied = effects.apply(outcome("003.00", 13, :merged))

      aggregate_failures do
        expect(applied).to have_attributes(to: :approved)
        expect(plan("003.00").status.key).to eq(:approved)
        expect(plan("003.00").pull_requests.map(&:state)).to eq(["Merged 🟣"])
      end
    end

    it "waits for the plan's other open pull request" do
      plans { |t| t.plan "003.00", :in_review, "half", files:, prs: [t.open(13, "c"), t.open(16, "f")] }
      applied = effects.apply(outcome("003.00", 13, :merged))

      aggregate_failures do
        expect(applied).to have_attributes(to: nil)
        expect(plan("003.00").status.key).to eq(:in_review)
        expect(plan("003.00").pull_requests.map(&:state)).to eq(["Merged 🟣", "Open 🟡"])
      end
    end
  end

  describe "a pull request closed unmerged" do
    it "moves the plan to ❌, with discarded.md naming it" do
      plans { |t| t.plan "004.00", :in_review, "closed", files:, prs: [t.open(14, "d")] }
      applied = effects.apply(outcome("004.00", 14, :closed))

      aggregate_failures do
        expect(applied).to have_attributes(to: :discarded)
        expect(plan("004.00").status.key).to eq(:discarded)
        expect(plan("004.00").read("discarded.md")).to include("#14")
        expect(plan("004.00").pull_requests.map(&:state)).to eq(["Closed 🔴"])
      end
    end

    it "keeps a plan whose other pull request merged" do
      plans { |t| t.plan "004.00", :in_review, "mixed", files:, prs: [t.open(14, "d"), t.merged(15, "e")] }
      effects.apply(outcome("004.00", 14, :closed))

      expect(plan("004.00").status.key).to eq(:in_review)
    end
  end

  describe "discarded.md" do
    it "leaves a hand-written note on a plan already at ❌ alone" do
      plans do |t|
        t.plan "005.00", :discarded, "gone", files: files.merge("discarded.md" => "# Discarded\n\nBy hand.\n"),
          prs: [t.open(17, "g")]
      end
      effects.apply(outcome("005.00", 17, :closed))

      expect(plan("005.00").read("discarded.md")).to eq("# Discarded\n\nBy hand.\n")
    end

    it "is taken back when the machine refuses the move" do
      plans { |t| t.plan "006.00", :in_review, "refused", files:, prs: [t.open(18, "h")] }
      allow(effects).to receive(:walk).and_return(nil)

      aggregate_failures do
        expect(effects.apply(outcome("006.00", 18, :closed))).to have_attributes(to: nil)
        expect(plan("006.00").read("discarded.md")).to be_nil
      end
    end
  end

  it "names the problem when no pull request state words an outcome" do
    stub_const("OpenLanes::Plans::PullRequests::STATES", [[/\bopen\b/i, "Open 🟡"]].freeze)
    plans { |t| t.plan "007.00", :in_review, "reworded", files:, prs: [t.open(19, "i")] }

    expect { effects.apply(outcome("007.00", 19, :merged)) }
      .to raise_error(OpenLanes::Error, /no pull request state matches "merged"/)
  end

  it "ignores a plan that is gone" do
    expect(effects.apply(outcome("099.00", 1, :merged))).to be_nil
  end
end
