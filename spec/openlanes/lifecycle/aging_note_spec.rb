# frozen_string_literal: true

RSpec.describe OpenLanes::Lifecycle::AgingNote, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:question) { "## B1 Which feed?\n" }
  let(:person) { "# Deferred\n\nRevisit once the vendor signs.\n" }

  def deferred(delayed, blocked: question)
    files = { "spec.md" => spec_body, "delayed.md" => delayed }
    files["blocked.md"] = blocked if blocked
    plans { |t| t.plan "001.00", :deferred, "feed", files: }
    tree.reload.find("001.00")
  end

  def note(fresh: true) = described_class.text(tree.reload.find("001.00"), on: Time.new(2026, 11, 1), blocked_for: "15 days", fresh:)

  # The note as the sweep writes it, which needs the plan it is written for.
  def aged(blocked: question)
    path = nil
    plans { |t| path = t.plan "001.00", :deferred, "feed", files: { "spec.md" => spec_body } }
    File.write(File.join(path, "delayed.md"), note)
    File.write(File.join(path, "blocked.md"), blocked) if blocked
    tree.reload.find("001.00")
  end

  describe ".waiting?" do
    it "is true for a plan aging deferred with its questions still there" do
      expect(described_class.waiting?(aged)).to be(true)
    end

    it "is false once blocked.md is gone" do
      expect(described_class.waiting?(aged(blocked: nil))).to be(false)
    end

    it "is false for a plan a person deferred, even one with a blocked.md" do
      expect(described_class.waiting?(deferred(person))).to be(false)
    end

    it "is false for a plan in any other state" do
      plans { |t| t.plan "002.00", :blocked, "other", files: { "blocked.md" => question, "delayed.md" => "x" } }

      expect(described_class.waiting?(tree.reload.find("002.00"))).to be(false)
    end
  end

  describe ".retire" do
    it "deletes a delayed.md that held nothing but the aging note" do
      path = aged.feature.path

      expect([described_class.retire(path), File.exist?(File.join(path, "delayed.md"))]).to eq([true, false])
    end

    it "keeps what a person wrote, so their deferral still stands" do
      subject = deferred(person + note(fresh: false))
      described_class.retire(subject.feature.path)

      expect(File.read(File.join(subject.feature.path, "delayed.md"))).to eq(person)
    end

    it "leaves a person's delayed.md alone" do
      subject = deferred(person)

      expect([described_class.retire(subject.feature.path), subject.read("delayed.md")]).to eq([false, person])
    end

    it "has nothing to do without a delayed.md" do
      plans { |t| t.plan "002.00", :new, "bare", files: { "spec.md" => spec_body } }

      expect(described_class.retire(tree.reload.find("002.00").feature.path)).to be(false)
    end
  end
end
