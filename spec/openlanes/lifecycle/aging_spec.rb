# frozen_string_literal: true

require "json"

# The clock is never stubbed here. Each plan's age comes from a `Blocked`
# signature backdated in its real `state.json`, which is where a real run
# reads it from, so the fixture says what the sweep sees.
RSpec.describe OpenLanes::Lifecycle::Aging, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:day) { 86_400 }
  let(:question) { "## B1 Which feed?\n" }

  def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

  # A blocked plan whose `Blocked` signature is +days+ old.
  def blocked(ordinal, slug, days:, status: :blocked, spec: spec_body)
    path = nil
    plans { |t| path = t.plan ordinal, status, slug, files: { "spec.md" => spec, "blocked.md" => question } }
    sign(path, Time.now - (days * day))
    path
  end

  def sign(path, at)
    OpenLanes::Plans::PlanState.for(path).sign!(agent: "backend-coder", round: 1, status: "Blocked", note: "technical", at:)
  end

  # A plan that waits for +on+, in the given state.
  def dependent(ordinal, on:, status: :planned)
    plans do |t|
      t.plan ordinal, status, "consumer", files: { "spec.md" => needs(on), "plan.md" => "# P\n\n## U1\n" }
    end
  end

  def state_of(ordinal) = tree.reload.find(ordinal).status.key

  def sweep(since: nil, commit: true) = described_class.new(tree: tree.reload, since:).call(commit:)

  describe "the limits" do
    it "lives in one place, as 24 hour multiples" do
      expect([described_class::BOMB_AFTER, described_class::DEFER_AFTER]).to eq([7 * 86_400, 14 * 86_400])
    end
  end

  describe "#started_at" do
    it "starts at the latest Blocked signature, so a re-block restarts the clock" do
      path = blocked("001.00", "feed", days: 20)
      sign(path, Time.now - (2 * day))

      expect(described_class.new(tree:).age_of(tree.find("001.00"))).to be_within(60).of(2 * day)
    end

    it "falls back to blocked.md's mtime when nobody signed" do
      path = nil
      plans { |t| path = t.plan "001.00", :blocked, "feed", files: { "spec.md" => spec_body, "blocked.md" => question } }
      File.utime(Time.now - (9 * day), Time.now - (9 * day), File.join(path, "blocked.md"))

      expect(described_class.new(tree:).age_of(tree.find("001.00"))).to be_within(60).of(9 * day)
    end

    it "never starts before aging_since, so paused weeks do not count" do
      blocked("001.00", "feed", days: 30)

      since = Date.today - 3
      started = described_class.new(tree:, since:).started_at(tree.find("001.00"))
      expect(started).to eq(Time.local(since.year, since.month, since.day))
    end
  end

  context "when a blocked plan has an open dependent" do
    before do
      blocked("001.00", "feed", days: 8)
      dependent("002.00", on: "001.00")
    end

    it "turns it into a 💣 after seven days, and reports it" do
      result = sweep

      aggregate_failures do
        expect(result.bombed).to eq(%w[001.00])
        expect(result.deferred).to be_empty
        expect(state_of("001.00")).to eq(:bomb)
      end
    end

    it "ages nothing when aging_since is today" do
      expect(sweep(since: Date.today).bombed).to be_empty
      expect(state_of("001.00")).to eq(:blocked)
    end

    it "renames nothing on a dry run, and says what it would bomb" do
      expect(sweep(commit: false).bombed).to eq(%w[001.00])
      expect(state_of("001.00")).to eq(:blocked)
    end

    it "does the same from a product block" do
      FileUtils.rm_rf(tree.find("001.00").feature.path)
      blocked("001.00", "feed", days: 8, status: :product_blocked)

      sweep
      expect(state_of("001.00")).to eq(:bomb)
    end
  end

  # Another process (a hand rename, a second engine) can move the folder
  # between the sweep's read and its rename; the machine then refuses, and
  # the sweep says so at warn and moves on rather than raising.
  context "when the state machine refuses the move" do
    before do
      allow(OpenLanes::Plans::StateMachine).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { allow(it).to receive(:promote!).and_raise(OpenLanes::Plans::StateMachine::Refused, "moved under us") }
      end
      allow(OpenLanes::UI).to receive(:log)
    end

    it "bombs nothing, and logs why" do
      blocked("001.00", "feed", days: 8)
      dependent("002.00", on: "001.00")

      aggregate_failures do
        expect(sweep.bombed).to be_empty
        expect(OpenLanes::UI).to have_received(:log).with("aging: could not bomb: moved under us", level: :warn, plan: "001.00")
      end
    end

    it "defers nothing, takes its delayed.md back, and logs why" do
      path = blocked("001.00", "feed", days: 15)

      aggregate_failures do
        expect(sweep.deferred).to be_empty
        expect(File.exist?(File.join(path, "delayed.md"))).to be(false)
        expect(OpenLanes::UI).to have_received(:log).with("aging: could not defer: moved under us", level: :warn, plan: "001.00")
      end
    end
  end

  it "reads an unparseable signature time as no signature, and falls back to blocked.md" do
    path = blocked("001.00", "feed", days: 20)
    state = File.join(path, "state.json")
    File.write(state, File.read(state).gsub(/"at": ?"[^"]+"/, '"at": "not a time"'))
    File.utime(Time.now - (3 * day), Time.now - (3 * day), File.join(path, "blocked.md"))

    expect(described_class.new(tree:).age_of(tree.find("001.00"))).to be_within(60).of(3 * day)
  end

  it "leaves a blocked plan with a dependent alone before seven days" do
    blocked("001.00", "feed", days: 6)
    dependent("002.00", on: "001.00")

    expect(sweep.bombed).to be_empty
  end

  context "when nobody waits for the blocked plan" do
    it "defers it after fourteen days, with a delayed.md the Deferred invariant accepts" do
      blocked("001.00", "feed", days: 15)
      result = sweep
      subject = tree.reload.find("001.00")

      aggregate_failures do
        expect(result.deferred).to eq(%w[001.00])
        expect(subject.status.key).to eq(:deferred)
        expect(subject).to be_consistent
        expect(subject.read("delayed.md")).to include("revisit after the block is answered", "Deferred by aging")
        expect(subject.read("blocked.md")).to eq(question)
      end
    end

    it "leaves it blocked before fourteen days, even past seven" do
      blocked("001.00", "feed", days: 10)
      expect(sweep.deferred).to be_empty
      expect(state_of("001.00")).to eq(:blocked)
    end

    it "writes no delayed.md on a dry run" do
      blocked("001.00", "feed", days: 15)

      expect(sweep(commit: false).deferred).to eq(%w[001.00])
      expect(tree.reload.find("001.00").file?("delayed.md")).to be(false)
    end

    it "counts a dependent that shipped or was dropped as nobody" do
      blocked("001.00", "feed", days: 15)
      dependent("002.00", on: "001.00", status: :discarded)

      expect(sweep.deferred).to eq(%w[001.00])
    end
  end

  it "never touches a 💣, nor any plan that is not blocked" do
    blocked("001.00", "feed", days: 30)
    tree.reload.find("001.00").machine.promote!(:bomb)
    plans { |t| t.plan "003.00", :planned, "other", files: { "spec.md" => spec_body, "plan.md" => "# P\n\n## U1\n" } }

    result = sweep
    expect([result.bombed, result.deferred]).to eq([[], []])
    expect(state_of("001.00")).to eq(:bomb)
  end

  it "ages only the plans it is given" do
    blocked("001.00", "feed", days: 15)
    result = described_class.new(tree:).call(subjects: [], commit: true)

    expect(result.deferred).to be_empty
  end

  it "is reached through the Lifecycle facade" do
    blocked("001.00", "feed", days: 15)
    expect(OpenLanes::Lifecycle.age(tree:, commit: false).deferred).to eq(%w[001.00])
  end
end
