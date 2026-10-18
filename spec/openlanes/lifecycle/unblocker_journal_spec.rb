# frozen_string_literal: true

# M3: every answered question goes into the journal of the agent that asked
# it, B1 with A1, before the broker folds it in and the words are gone.
RSpec.describe OpenLanes::Lifecycle::Unblocker, :tree do
  subject(:unblocker) { described_class.new(tree:, agent:, executor:, commit:) }

  let(:commit) { true }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agent) { OpenLanes::Agents::Registry.new.find("lando-broker") }
  let(:seen) { [] }
  # Deletes blocked.md, as the broker does once the last question folds in,
  # after noting what the asker's journal held when it was invoked.
  let(:executor) do
    lambda { |_agent, subject, **|
      seen << OpenLanes::Plans::PlanState.for(subject.feature.path).journal("yoda-writer").flat_map(&:entries)
      FileUtils.rm_f(File.join(subject.feature.path, "blocked.md"))
      [true, "completed"]
    }
  end
  let(:blocked_body) do
    <<~MARKDOWN
      # Blocked

      ## B1 Which vendor

      We need a payment vendor.

      a) Acme Pay (Recommended)
      b) Example Billing

      ## A1

      a) Acme Pay

      Answered by sample-user on 2026-10-16
      <!-- cmd:0123456789abcdef -->

      ## B2 Unanswered

      Still open.
    MARKDOWN
  end
  let(:subject_plan) do
    plans { |t| t.plan("001.00", :blocked, "a-feature", files: { "spec.md" => spec_body, "blocked.md" => blocked_body }) }
    tree.reload.find("001.00")
  end
  let(:state) { OpenLanes::Plans::PlanState.for(subject_plan.feature.path) }

  before { state.stage!(agent: "yoda-writer", round: 1, status: "Blocked", started_at: Time.now.iso8601) }

  it "records each answered question, with its answer, in the asker's journal before the broker runs" do
    unblocker.drain(subject_plan)
    expect(seen.first.map(&:to_json_h)).to eq([{
      "kind"   => "question",
      "text"   => "B1 Which vendor We need a payment vendor. a) Acme Pay (Recommended) b) Example Billing",
      "ref"    => "B1",
      "answer" => "a) Acme Pay Answered by sample-user on 2026-10-16"
    }])
  end

  context "when the answer is written on its heading" do
    let(:blocked_body) { "# Blocked\n\n## B1. What happens on revocation\n\n## A1. Retain, do not delete\n" }

    it "records the heading's words as the answer" do
      unblocker.drain(subject_plan)
      expect(seen.first.map(&:answer)).to eq(["Retain, do not delete"])
    end
  end

  context "when nothing on record ever blocked" do
    before { FileUtils.rm_f(state.path) }

    it "drains without recording" do
      unblocker.drain(subject_plan)
      expect(seen.first).to eq([])
    end
  end

  context "when it is a dry run" do
    let(:commit) { false }

    it "records nothing" do
      unblocker.drain(subject_plan)
      expect(state.journal("yoda-writer")).to eq([])
    end
  end

  # M2 for the broker itself: its prompt asks it to keep a journal, and no
  # dispatcher job carries its progress, so the unblocker writes it.
  context "when the broker prints journal lines and then fails" do
    let(:decision) { OpenLanes::Plans::Journal::Entry.new(kind: "decision", text: "Folded B1 into spec.md") }
    let(:update) { Struct.new(:journal) }
    let(:executor) do
      lambda { |_agent, _subject, **, &progress|
        progress.call(update.new([decision]))
        progress.call(update.new([decision]))
        [false, "exited 1"]
      }
    end

    def broker_entries = state.journal("lando-broker").flat_map(&:entries).map(&:text)

    it "keeps them, once, when the run loop drains the plan" do
      unblocker.drain(subject_plan)
      expect(broker_entries).to eq(["Folded B1 into spec.md"])
    end

    it "keeps them, once, when `openlanes unblock` runs it" do
      unblocker.call([subject_plan])
      expect(broker_entries).to eq(["Folded B1 into spec.md"])
    end
  end

  context "when state.json cannot be read" do
    let(:executor) { ->(_agent, _subject, **) { [true, "completed"] } }
    let(:heard) { [] }
    let!(:tap) { OpenLanes::UI.tap_log(->(message, _) { heard << message }) }

    after { OpenLanes::UI.untap_log(tap) }

    it "says so and drains anyway" do
      File.write(state.path, "{")
      outcome = unblocker.drain(subject_plan)
      expect([outcome.ok, heard.grep(/journal not written/).size]).to eq([true, 1])
    end
  end
end
