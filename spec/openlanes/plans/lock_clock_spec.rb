# frozen_string_literal: true

# R6: the refactor's global lock lapses refactor.lock_hours after it was taken.
RSpec.describe OpenLanes::Plans::LockClock, :tree do
  subject(:clock) { described_class.new }

  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:locked) { "---\nexecution: global-lock-required\n---\n# Plan\n" }
  let(:now) { Time.utc(2026, 11, 8, 12) }

  def state(ordinal) = OpenLanes::Plans::PlanState.for(Dir.glob(File.join(plans_root, "#{ordinal}*")).first)
  def lock(at: now) = OpenLanes::Plans::GlobalLock.new(tree.reload, ttl: 3600, now: at)

  context "when a refactor takes the lock" do
    before do
      plans do |t|
        t.plan "031.00", :planned, "rename", files: { "spec.md" => spec_body, "plan.md" => locked }
        t.plan "040.00", :new, "fresh", files: { "spec.md" => spec_body }
      end
    end

    it "records the moment once, and leaves plans that are not refactors alone" do
      clock.call(lock, now:)
      clock.call(lock(at: now + 60), now: now + 60)

      expect([state("031.00").global_lock_taken_at, state("040.00").exist?]).to eq([now, false])
    end

    it "keeps a lapsed lock's time, so the refactor is not handed a fresh one" do
      state("031.00").take_global_lock!(at: now - 7200)
      clock.call(lock, now:)

      expect(state("031.00").global_lock_taken_at).to eq(now - 7200)
    end
  end

  context "when a refactor stops asking for the lock" do
    before do
      plans do |t|
        t.plan "031.00", :approved, "rename", files: { "spec.md" => spec_body, "plan.md" => locked }
        t.plan "032.00", :ready_for_planning, "unplanned", files: { "spec.md" => spec_body, "plan.md" => locked }
      end
      state("031.00").take_global_lock!(at: now - 600)
    end

    it "forgets when it was taken, and writes no state for one that never had any" do
      clock.call(lock, now:)

      expect([state("031.00").global_lock_taken_at, state("032.00").exist?]).to eq([nil, false])
    end
  end
end
