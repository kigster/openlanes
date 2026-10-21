# frozen_string_literal: true

# The edges of the loop's one verification object that the dispatcher's
# own spec does not reach: GitHub failing, and the pace of the CI look.
RSpec.describe OpenLanes::Engine::Verification::Driver, :tree do
  subject(:driver) { described_class.new(outcome:, worktree:, clock: -> { now.first }, interval: 15) }

  let(:outcome) { instance_double(OpenLanes::Engine::Verification::Outcome) }
  let(:checkout) { instance_double(OpenLanes::Vcs::Worktree::Checkout) }
  let(:worktree) { instance_double(OpenLanes::Vcs::Worktree, checkout_for: checkout) }
  let(:now) { [0.0] }
  let(:files) { { "spec.md" => spec_body, "plan.md" => "# Plan\n" } }
  let(:waiting) { OpenLanes::Engine::Verification::Outcome::Result.new(kind: :waiting, note: "🧪 waiting on CI for PR #7") }

  def plan = OpenLanes::Plans::Tree.new(dir: plans_root).find(OpenLanes::Plans::Ordinal.parse("014.00"))

  def verified!(number = 1, published: true)
    dir = File.join(plan.feature.path, "verification", number.to_s)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "report.md"), "Verdict: verified\n")
    File.write(File.join(dir, "published.txt"), "abc1234\n") if published
  end

  describe "#hand_off" do
    before { plans { |t| t.plan "014.00", :in_review, "x", files:, prs: [t.open(7, "X")] } }

    it "keeps the plan at 👀 and says why when GitHub cannot be asked" do
      allow(outcome).to receive(:labels).and_raise(OpenLanes::Error, "could not read labels of #7: offline")

      aggregate_failures do
        expect(driver.hand_off(plan)).to eq("stays 👀: could not read labels of #7: offline")
        expect(plan.status.key).to eq(:in_review)
      end
    end

    it "keeps the plan at 👀 when the pull request is built from another branch" do
      allow(outcome).to receive_messages(labels: %w[review-approved], mismatch: "verification refused — #7 is built from x, not y, so a push would not reach it")

      aggregate_failures do
        expect(driver.hand_off(plan)).to eq("stays 👀: verification refused — #7 is built from x, not y, so a push would not reach it; verify it by hand")
        expect(plan.status.key).to eq(:in_review)
        expect(outcome).to have_received(:mismatch).with(checkout:, pull: anything)
      end
    end

    it "says a pull request with no review label carries nothing that goes on" do
      allow(outcome).to receive(:labels).and_return([])

      expect(driver.hand_off(plan)).to include("is labelled nothing")
    end
  end

  describe "#hand_off after an earlier verification" do
    before do
      plans { |t| t.plan "014.00", :in_review, "x", files:, prs: [t.open(7, "X")] }
      verified!
      allow(outcome).to receive_messages(labels: %w[review-approved], mismatch: nil)
    end

    it "starts a round of its own, so the old verified one is not taken for this hand-off" do
      driver.hand_off(plan)

      aggregate_failures do
        expect(plan.status.key).to eq(:verifying)
        expect(OpenLanes::Engine::Verification.latest(plan.feature.path).number).to eq(2)
        expect(driver.awaiting_ci?(plan)).to be(false)
      end
    end
  end

  # Plan 035: under mvp an approved pull request is not run through chewie.
  # Its round is written skipped and published by the engine, so the plan
  # waits on CI and the coverage gate at 🧪 as a verified one would, without
  # a later reader taking the report for chewie's own verdict.
  describe "#hand_off of an approved pull request under mvp" do
    subject(:driver) { described_class.new(outcome:, worktree:, quality: -> { quality }) }

    before do
      plans { |t| t.plan "014.00", :in_review, "x", files:, prs: [t.open(7, "X")] }
      allow(outcome).to receive_messages(labels: labels, mismatch: nil)
    end

    let(:labels) { %w[review-approved] }
    let(:quality) { :mvp }

    it "skips chewie, writes a skipped verdict, and waits on CI" do
      said = driver.hand_off(plan)
      report = File.read(OpenLanes::Engine::Verification.latest(plan.feature.path).report_path)

      aggregate_failures do
        expect(said).to eq("on to 🧪, verification skipped: PR #7 is review-approved and " \
                           "desired_codebase_quality is mvp; waiting on CI")
        expect(plan.status.key).to eq(:verifying)
        expect(driver.awaiting_ci?(plan)).to be(true)
        expect(report).to include("Verdict: skipped (mvp)")
        expect(report).not_to match(/^Verdict:\s*verified/i)
        expect(OpenLanes::Engine::Verification::Report.parse(report).verdict).to eq(:skipped)
      end
    end

    context "with standard" do
      let(:quality) { :standard }

      it "goes on to chewie" do
        expect(driver.hand_off(plan)).to eq("on to 🧪 verification")
        expect(driver.awaiting_ci?(plan)).to be(false)
      end
    end

    context "with an ok-not-perfect verdict" do
      let(:labels) { %w[review-ok-not-perfect] }

      it "goes on to chewie" do
        expect(driver.hand_off(plan)).to eq("on to 🧪 verification")
      end
    end
  end

  describe "#awaiting_ci?" do
    before { plans { |t| t.plan "014.00", :verifying, "x", files:, prs: [t.open(7, "X")] } }

    it "is false for a verified report the engine never published" do
      verified!(published: false)

      expect(driver.awaiting_ci?(plan)).to be(false)
    end

    it "is true once the engine has published it" do
      verified!

      expect(driver.awaiting_ci?(plan)).to be(true)
    end
  end

  describe "#pass" do
    before do
      plans { |t| t.plan "014.00", :verifying, "x", files:, prs: [t.open(7, "X")] }
      verified!(published: false)
    end

    let(:task) { instance_double(OpenLanes::Engine::Runner::Task, checkout:) }

    it "records the pushed commit, and only then does the plan wait on CI" do
      allow(outcome).to receive(:pass)
        .and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :committed, note: "x", sha: "abc1234def"))
      driver.pass(task, plan)

      expect(File.read(File.join(plan.feature.path, "verification", "1", "published.txt"))).to eq("abc1234def\n")
      expect(driver.awaiting_ci?(plan)).to be(true)
    end

    it "records nothing when the round was sent back" do
      allow(outcome).to receive(:pass)
        .and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :rejected, note: "x", to: :rejected))
      driver.pass(task, plan)

      expect(File).not_to exist(File.join(plan.feature.path, "verification", "1", "published.txt"))
    end
  end

  describe "#hand_off on a folder that cannot be 🧪" do
    before { plans { |t| t.plan "014.00", :in_review, "x", files: } }

    it "answers nothing, so the plan finishes at 👀 as before" do
      expect(driver.hand_off(plan)).to be_nil
    end
  end

  describe "#poll" do
    before do
      plans { |t| t.plan "014.00", :verifying, "x", files:, prs: [t.open(7, "X")] }
      verified!
      allow(outcome).to receive(:look).and_return(look)
    end

    let(:look) { OpenLanes::Engine::Verification::Outcome::Look.new(ci: :pending) }
    let(:ready) { OpenLanes::Engine::Verification::Outcome::Result.new(kind: :ready, note: "ready") }

    it "looks at once, then not again until the interval has passed" do
      allow(outcome).to receive(:settle).and_return(waiting)

      driver.poll([plan])
      driver.join
      first = driver.poll([plan])
      now[0] = 10.0
      driver.poll([plan])
      now[0] = 15.0
      driver.poll([plan])
      driver.join

      aggregate_failures do
        expect(first.map(&:plan)).to eq(["014.00"])
        expect(outcome).to have_received(:look).twice
      end
    end

    it "only reads on its thread, and acts on what it read on the caller's" do
      threads = { look: nil, settle: nil }
      allow(outcome).to receive(:look) { threads[:look] = Thread.current and look }
      allow(outcome).to receive(:settle) { threads[:settle] = Thread.current and waiting }

      driver.poll([plan])
      driver.join
      driver.poll([plan])

      aggregate_failures do
        expect(threads[:look]).not_to eq(Thread.current)
        expect(threads[:settle]).to eq(Thread.current)
        expect(outcome).to have_received(:settle).with(checkout:, plan: anything, pull: anything, round: anything, seen: look)
      end
    end

    it "is busy, and names the plan it looks at, until what it found is acted on" do
      gate = Queue.new
      allow(outcome).to receive(:look) { gate.pop and look }
      allow(outcome).to receive(:settle).and_return(waiting)

      driver.poll([plan])
      during = [driver.busy?, driver.looking]
      gate << true
      driver.join
      finished = driver.busy?
      driver.poll([plan])

      expect([during, finished, driver.busy?, driver.looking]).to eq([[true, ["014.00"]], true, false, []])
    end

    it "leaves a plan that moved while it was looked at for the next look" do
      allow(outcome).to receive(:settle)

      driver.poll([plan])
      driver.join
      plan.machine.promote!(:rejected)

      aggregate_failures do
        expect(driver.poll([plan])).to eq([])
        expect(outcome).not_to have_received(:settle)
      end
    end

    it "logs one plan's failure and carries on with the next look" do
      allow(outcome).to receive(:look).and_raise(JSON::ParserError, "unexpected token")
      allow(OpenLanes::UI).to receive(:log)

      driver.poll([plan])
      driver.join

      aggregate_failures do
        expect(driver.poll([plan])).to eq([])
        expect(OpenLanes::UI).to have_received(:log).with("verification not settled: unexpected token", level: :warn, plan: "014.00")
      end
    end

    it "stops looking at a plan once it is ready-to-merge" do
      allow(outcome).to receive(:settle).and_return(ready)

      driver.poll([plan])
      driver.join
      driver.poll([plan])
      now[0] = 30.0
      driver.poll([plan])
      driver.join

      expect(outcome).to have_received(:look).once
    end

    it "looks again at a plan verified afresh after it was ready-to-merge" do
      allow(outcome).to receive(:settle).and_return(ready)

      driver.poll([plan])
      driver.join
      driver.poll([plan])
      verified!(2)
      now[0] = 30.0
      driver.poll([plan])
      driver.join

      expect(outcome).to have_received(:look).twice
    end
  end

  describe "a plan with no open pull request" do
    before { plans { |t| t.plan "014.00", :verifying, "x", files:, prs: [t.merged(7, "X")] } }

    it "has nothing to reject or pass" do
      task = instance_double(OpenLanes::Engine::Runner::Task, checkout: nil)

      expect([driver.reject(task, plan), driver.pass(task, plan)]).to eq([nil, nil])
    end
  end
end
