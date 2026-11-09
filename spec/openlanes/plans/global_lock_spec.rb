# frozen_string_literal: true

# R6: a sweeping refactor is built, reviewed and merged alone.
RSpec.describe OpenLanes::Plans::GlobalLock, :tree do
  subject(:lock) { described_class.new(tree) }

  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:locked) { "---\nexecution: global-lock-required\n---\n# Plan\n" }

  context "when no plan asks for the lock" do
    before do
      plans do |t|
        t.plan "010.00", :building, "work", files: { "spec.md" => spec_body }
        t.plan "020.00", :planned, "more", files: { "spec.md" => spec_body, "plan.md" => "# Plan\n" }
      end
    end

    it "holds nothing" do
      expect([lock.holder, lock.reason("010.00"), lock.reason("020.00")]).to eq([nil, nil, nil])
    end
  end

  context "when a refactor is still in the documents" do
    before do
      plans do |t|
        t.plan "031.00", :ready_for_planning, "rename", files: { "spec.md" => spec_body, "plan.md" => locked }
        t.plan "040.00", :new, "fresh", files: { "spec.md" => spec_body }
      end
    end

    it "locks nothing yet" do
      expect([lock.holder, lock.reason("040.00")]).to eq([nil, nil])
    end
  end

  context "when a planned refactor waits on open branches" do
    before do
      plans do |t|
        t.plan "018.00", :blocked, "stuck", files: { "spec.md" => spec_body, "contract.md" => "# Contract\n" }
        t.plan "020.00", :building, "busy", files: { "spec.md" => spec_body }
        t.plan "025.00", :blocked, "asked-early", files: { "spec.md" => spec_body, "blocked.md" => "## B1 Which?\n" }
        t.plan "031.00", :planned, "rename", files: { "spec.md" => spec_body, "plan.md" => locked }
        t.plan "040.00", :new, "fresh", files: { "spec.md" => spec_body }
        t.plan "050.00", :approved, "shipped", files: { "spec.md" => spec_body }
      end
    end

    it "names every plan that still holds a branch, blocked ones included" do
      expect(lock.waits_on).to eq(%w[018.00 020.00])
      expect(lock.reason("031.00")).to eq("refactor 031.00 waits on 018.00 ⭕, 020.00 🟡")
    end

    it "lets plans holding a branch carry on, and queues those that never started" do
      expect(lock.reason("020.00")).to be_nil
      expect(lock.reason("040.00")).to eq("queued behind refactor 031.00")
      expect(lock.reason("025.00")).to eq("queued behind refactor 031.00")
    end
  end

  context "when a planned refactor has nothing to wait on" do
    before do
      plans do |t|
        t.plan "031.00", :planned, "rename", files: { "spec.md" => spec_body, "plan.md" => locked }
        t.plan "040.00", :new, "fresh", files: { "spec.md" => spec_body }
        t.plan "050.00", :discarded, "dropped", files: { "spec.md" => spec_body, "contract.md" => "# C\n" }
      end
    end

    it "frees the refactor and holds everything else" do
      expect(lock.reason("031.00")).to be_nil
      expect(lock.reason("040.00")).to eq("queued behind refactor 031.00")
    end
  end

  context "when the refactor is under way" do
    before do
      plans do |t|
        t.plan "031.00", :in_review, "rename", files: { "spec.md" => spec_body, "plan.md" => locked }
        t.plan "040.00", :planned, "next", files: { "spec.md" => spec_body, "plan.md" => "# Plan\n" }
      end
    end

    it "starts nothing else until it is merged" do
      expect(lock.holder).to eq("031.00")
      expect(lock.reason("031.00")).to be_nil
      expect(lock.reason("040.00")).to eq("queued behind refactor 031.00")
    end
  end

  context "when the refactor is merged" do
    before do
      plans do |t|
        t.plan "031.00", :approved, "rename", files: { "spec.md" => spec_body, "plan.md" => locked }
        t.plan "040.00", :planned, "next", files: { "spec.md" => spec_body, "plan.md" => "# Plan\n" }
      end
    end

    it "lets the rest go" do
      expect([lock.holder, lock.reason("040.00")]).to eq([nil, nil])
    end
  end

  context "when the refactor is blocked mid-build" do
    before do
      plans do |t|
        t.plan "031.00", :blocked, "rename", files: { "spec.md" => spec_body, "plan.md" => locked, "contract.md" => "# C\n" }
        t.plan "040.00", :planned, "next", files: { "spec.md" => spec_body, "plan.md" => "# Plan\n" }
      end
    end

    it "still holds everything else" do
      expect(lock.reason("040.00")).to eq("queued behind refactor 031.00")
    end
  end

  context "when a retroactive plan carries an open pull request" do
    before do
      plans do |t|
        t.plan "012.00", :retroactive, "adopted", files: { "spec.md" => spec_body, "pull-requests.md" => "# Pull Requests\n" }
        t.plan "031.00", :planned, "rename", files: { "spec.md" => spec_body, "plan.md" => locked }
      end
    end

    it "makes the refactor wait on it" do
      expect(lock.waits_on).to eq(["012.00"])
    end
  end
end
