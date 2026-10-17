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

  def verified!
    dir = File.join(plan.feature.path, "verification", "1")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "report.md"), "Verdict: verified\n")
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
    end

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
        expect(outcome).to have_received(:settle).twice
      end
    end

    it "logs one plan's failure and carries on with the next look" do
      allow(outcome).to receive(:settle).and_raise(JSON::ParserError, "unexpected token")
      allow(OpenLanes::UI).to receive(:log)

      driver.poll([plan])
      driver.join

      aggregate_failures do
        expect(driver.poll([plan])).to eq([])
        expect(OpenLanes::UI).to have_received(:log).with("verification not settled: unexpected token", level: :warn, plan: "014.00")
      end
    end

    it "stops looking at a plan once it is ready-to-merge" do
      allow(outcome).to receive(:settle).and_return(OpenLanes::Engine::Verification::Outcome::Result.new(kind: :ready, note: "ready"))

      driver.poll([plan])
      driver.join
      driver.poll([plan])
      now[0] = 30.0
      driver.poll([plan])
      driver.join

      expect(outcome).to have_received(:settle).once
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
