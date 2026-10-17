# frozen_string_literal: true

# R2 and R3 in docs/decisions/decisions-on-three-reviewers-and-auto-merge.md:
# the emoji each comment opens with, counted across every reviewer, decide
# the label.
RSpec.describe OpenLanes::Plans::Verdict do
  def comment(body, agent: "hansolo-reviewer") = { agent:, body: }
  def hmm(count, agent: "darth-reviewer") = Array.new(count) { comment("🤔 Hmmm... consider a guard #{it}", agent:) }

  let(:header) { comment("Reviewed by Hans Solo, reviewing agent, using Opus 5.5 by Anthropic at 2026/10/16 @ 12:34pm.") }
  let(:vader) { "vader-security-reviewer" }

  it "approves a clean pull request that earned no ✅ at all" do
    expect(described_class.call([header]).names).to eq(%w[review-approved])
  end

  it "approves with exactly max_hmm 🤔, and passes" do
    verdict = described_class.call(hmm(5) + [comment("✅ Great! the cache")])

    aggregate_failures do
      expect(verdict.names).to eq(%w[review-approved])
      expect(verdict).to be_passing
      expect(verdict.tally).to include(hmm: 5, great: 1)
    end
  end

  it "is ok-not-perfect past max_hmm, counting every reviewer together" do
    comments = hmm(3, agent: "hansolo-reviewer") + hmm(3, agent: "darth-reviewer")

    expect(described_class.call(comments).names).to eq(%w[review-ok-not-perfect])
  end

  it "takes the threshold it is given" do
    expect(described_class.call(hmm(2), max_hmm: 1).names).to eq(%w[review-ok-not-perfect])
  end

  it "rejects on a single ⛔️, however many ✅ surround it" do
    comments = [comment("✅ Great!"), comment("⛔️ Must Fix: nil call on user"), comment("✅ Great!")]
    verdict = described_class.call(comments)

    aggregate_failures do
      expect(verdict.names).to eq(%w[review-rejected])
      expect(verdict).not_to be_passing
    end
  end

  it "reads ⛔ without its variation selector as the same mark" do
    expect(described_class.call([comment("⛔ Must Fix: unbounded loop")]).names).to eq(%w[review-rejected])
  end

  it "rejects before it counts 🤔" do
    expect(described_class.call(hmm(9) + [comment("⛔️ Must Fix")]).names).to eq(%w[review-rejected])
  end

  it "adds review-vulnerability beside review-rejected for vader's 💣" do
    verdict = described_class.call([comment("💣 Security Flaw: SQL built from params", agent: vader)])

    expect(verdict.names).to eq(%w[review-rejected review-vulnerability])
  end

  it "counts vader's 🔓 without blocking anything" do
    verdict = described_class.call([comment("🔓 Security Concern: token logged at debug", agent: vader)])

    aggregate_failures do
      expect(verdict.names).to eq(%w[review-approved])
      expect(verdict.tally[:concern]).to eq(1)
    end
  end

  it "ignores 💣 and 🔓 from anyone but vader, and says which" do
    stray = [comment("💣 Security Flaw: eval", agent: "darth-reviewer"), comment("🔓 Security Concern", agent: nil)]
    verdict = described_class.call(stray)

    aggregate_failures do
      expect(verdict.names).to eq(%w[review-approved])
      expect(verdict.tally.values.sum).to eq(0)
      expect(verdict.ignored.map(&:agent)).to eq(["darth-reviewer", nil])
    end
  end

  it "ignores comments that open with anything else, emoji later in the text included" do
    comments = [comment("Looks fine ⛔️ maybe"), comment("👍🏼 to deploy"), comment("")]

    expect(described_class.call(comments).tally.values.sum).to eq(0)
  end

  it "reads through markdown before the emoji: a heading, a quote, bold" do
    comments = [comment("## ⛔️ Must Fix"), comment("> 🤔 Hmmm..."), comment("**✅ Great!**")]

    expect(described_class.call(comments, max_hmm: 0).tally).to include(must_fix: 1, hmm: 1, great: 1)
  end

  it "takes Comment values and string-keyed hashes alike" do
    comments = [described_class::Comment.new(agent: vader, body: "💣 x"), { "agent" => "hansolo-reviewer", "body" => "⛔️ y" }]

    expect(described_class.call(comments).tally).to include(flaw: 1, must_fix: 1)
  end

  describe "through the Plans facade" do
    around do |example|
      saved = ENV.fetch("OPENLANES_REVIEW_MAX_HMM", nil)
      example.run
    ensure
      saved ? ENV["OPENLANES_REVIEW_MAX_HMM"] = saved : ENV.delete("OPENLANES_REVIEW_MAX_HMM")
    end

    it "takes max_hmm from the environment over the file and the default" do
      ENV["OPENLANES_REVIEW_MAX_HMM"] = "1"

      expect(OpenLanes::Plans.verdict(hmm(2)).names).to eq(%w[review-ok-not-perfect])
    end

    it "logs a warning for each mark it ignored" do
      allow(OpenLanes::UI).to receive(:log)

      OpenLanes::Plans.verdict([comment("💣 eval", agent: "darth-reviewer")], max_hmm: 5)

      expect(OpenLanes::UI).to have_received(:log)
        .with(a_string_including("ignored 💣 from darth-reviewer", "only vader-security-reviewer"), level: :warn)
    end
  end
end
