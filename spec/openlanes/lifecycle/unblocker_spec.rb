# frozen_string_literal: true

RSpec.describe OpenLanes::Lifecycle::Unblocker, :tree do
  subject(:unblocker) { described_class.new(tree:, agent:, executor:, commit: true) }

  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agent) { OpenLanes::Agents::Registry.new.find("unblocker") }

  # The seam. Nothing in the suite invokes `claude`; this stands in for the
  # agent and edits `blocked.md` the way `unblocker` would.
  let(:executor) { ->(_agent, _subject, **) { [true, "completed"] } }

  let(:blocked_body) do
    <<~MARKDOWN
      # Blocked

      ## B1. Which vendor

      ## B2. What happens on revocation

      ## A2. Retain, do not delete

      Decided by Alan Turing <alan.turing@manchester.edu>, 2026-08-01.
    MARKDOWN
  end

  def blocked_plan(ordinal = "001.00", body: blocked_body)
    plans { |t| t.plan(ordinal, :blocked, "a-feature", files: { "spec.md" => spec_body, "blocked.md" => body }) }
    tree.reload.find(ordinal)
  end

  # What `unblocker` does when it folds one question in: the `## B<n>`
  # heading goes, and the file goes with the last of them.
  def folding(*numbers)
    lambda do |_agent, subject, **|
      path = File.join(subject.feature.path, "blocked.md")
      kept = File.read(path).split(/^(?=\#\# )/).reject { |s| numbers.any? { |n| s.start_with?("## B#{n}") } }
      remaining = kept.join
      remaining.match?(OpenLanes::Plans::OPEN_BLOCK) ? File.write(path, remaining) : File.delete(path)
      [true, "completed"]
    end
  end

  describe "#resolve" do
    it "finds the plan a number names" do
      blocked_plan

      expect(unblocker.resolve(["001"]).first).to be_drainable
    end

    # Stopping at the first bad token hid the rest of the answer: a run naming
    # four plans reported one problem and said nothing about the other three.
    it "reports a number that names no folder rather than stopping there" do
      blocked_plan

      expect(unblocker.resolve(["999", "001"]).map(&:problem)).to eq([:missing, nil])
    end

    it "refuses a folder that was never stopped, and says which" do
      plans { |t| t.plan("002.00", :new, "unstopped", files: { "spec.md" => spec_body }) }

      expect(unblocker.resolve(["002"]).first.problem).to eq(:not_blocked)
    end

    it "splits a comma separated list the way a shell hands one over" do
      blocked_plan
      plans { |t| t.plan("002.00", :blocked, "another", files: { "spec.md" => spec_body, "blocked.md" => blocked_body }) }

      expect(tree.reload && unblocker.resolve(["001,002"]).size).to eq(2)
    end

    # ⭕ is derived from `blocked.md`, so gating the drain on the emoji made
    # the tool circular: a file numbered some other way never earned the emoji,
    # so `unblock` refused it, so it could never be fixed.
    it "gates on the file, not on the folder's emoji" do
      plans { |t| t.plan("003.00", :new, "mislabelled", files: { "spec.md" => spec_body, "blocked.md" => "## Q1 huh" }) }

      expect(tree.reload && unblocker.resolve(["003"]).first).to be_drainable
    end
  end

  describe ".questions" do
    it "reads each `## B<n>` heading as its own question" do
      expect(described_class.questions(blocked_plan).map(&:number)).to eq([1, 2])
    end

    it "marks the ones whose `## A<n>` is sitting there unfolded" do
      expect(described_class.questions(blocked_plan).map(&:answered)).to eq([false, true])
    end

    it "says so in the line it prints, so nobody has to cross-reference" do
      expect(described_class.questions(blocked_plan).last.to_s).to end_with("← answer waiting")
    end

    it "finds nothing in a file that numbers its questions some other way" do
      plans { |t| t.plan("004.00", :new, "unreadable", files: { "blocked.md" => "## Question one\n" }) }

      expect(described_class.questions(tree.reload.find("004.00"))).to be_empty
    end
  end

  describe "#call" do
    # An agent that says "done" and wrote nothing is a real failure mode, and
    # the only thing that can contradict it is the file.
    it "counts what the file lost, not what the agent claimed" do
      subject_plan = blocked_plan
      outcome = described_class.new(tree:, agent:, executor: folding(2), commit: true).call([subject_plan]).first

      expect(outcome.folded).to eq([2])
    end

    it "reports nothing folded when the agent left the file alone" do
      expect(unblocker.call([blocked_plan]).first.folded).to be_empty
    end

    # A partial drain is a normal, successful run: whatever is still open keeps
    # the plan blocked, correctly.
    it "leaves the questions nobody answered open, and says so" do
      subject_plan = blocked_plan
      outcome = described_class.new(tree:, agent:, executor: folding(2), commit: true).call([subject_plan]).first

      aggregate_failures do
        expect(outcome.after.map(&:number)).to eq([1])
        expect(outcome).not_to be_cleared
      end
    end

    it "notices when the last question went and the file with it" do
      subject_plan = blocked_plan
      outcome = described_class.new(tree:, agent:, executor: folding(1, 2), commit: true).call([subject_plan]).first

      expect(outcome).to be_cleared
    end

    # The folder is renamed out of ⭕ by the same resync pass the run loop
    # makes, so the outcome has to describe the folder as it stands now.
    it "reads the folder back under whatever name the drain left it with" do
      subject_plan = blocked_plan
      outcome = described_class.new(tree:, agent:, executor: folding(1, 2), commit: true).call([subject_plan]).first

      expect(outcome.subject.status.key).not_to eq(:blocked)
    end

    it "hands the executor the plan and the repository root" do
      seen = nil
      described_class.new(tree:,
        agent:,
        commit: true,
        executor: ->(_a, s, **kw) { seen = [s.feature.ordinal.to_s, kw[:root]] and [true, "ok"] })
                     .call([blocked_plan])

      expect(seen).to eq(["001.00", File.dirname(plans_root)])
    end

    # An agent that blows up must produce a report, not a backtrace: this is
    # the command a human runs to find out what happened.
    it "turns an exception into a failed outcome rather than a stack trace" do
      boom = ->(_a, _s, **) { raise "claude is not installed" }
      outcome = described_class.new(tree:, agent:, executor: boom, commit: true).call([blocked_plan]).first

      aggregate_failures do
        expect(outcome.ok).to be(false)
        expect(outcome.note).to include("claude is not installed")
      end
    end

    it "changes nothing when not committing" do
      subject_plan = blocked_plan
      described_class.new(tree:, agent:, executor: folding(1, 2), commit: false).call([subject_plan])

      expect(File.basename(tree.reload.find("001.00").feature.path)).to include("⭕")
    end

    it "has nothing to say about an empty list" do
      expect(unblocker.call([])).to eq([])
    end
  end

  describe "#drain, as the run loop calls it" do
    let(:subject_plan) { blocked_plan(body: "## B1. Which vendor\n\n## A1. Ours\n\nDecided by the CTO, 2026-10-13.\n") }

    let(:drained) { described_class.new(tree:, agent:, executor: folding(1), commit: applying).drain(subject_plan) }
    let(:applying) { true }

    it "hands one folder to the agent and counts what it folded, leaving the rename to the loop" do
      aggregate_failures do
        expect([drained.ok, drained.folded, drained.cleared?]).to eq([true, [1], true])
        expect(tree.reload.find("001.00").status.key).to eq(:blocked)
      end
    end

    context "with a dry run" do
      let(:applying) { false }

      it "invokes nobody" do
        expect([drained.ok, drained.note]).to eq([false, "not attempted: a dry run"])
      end
    end
  end
end
