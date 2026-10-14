# frozen_string_literal: true

RSpec.describe OpenLanes::Lifecycle::Lanes, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:subject_plan) { tree.reload.subjects.first }

  def plan_with(frontmatter, status: :new)
    plans { |t| t.plan "001.00", status, "task", files: { "spec.md" => "---\n#{frontmatter}\n---\n#{spec_body}" } }
  end

  describe ".target" do
    it "sends a plan-lane plan to 📋" do
      plan_with("lane: plan")
      expect(described_class.target(subject_plan).key).to eq(:ready_for_planning)
    end

    it "sends a quick-lane plan to ⭐️" do
      plan_with("lane: quick")
      expect(described_class.target(subject_plan).key).to eq(:planned)
    end

    it "leaves a full-lane plan where it is" do
      plan_with("lane: full")
      expect(described_class.target(subject_plan)).to be_nil
    end

    it "leaves a plan that is already past the phases its lane skips" do
      plans do |t|
        t.plan "001.00",
          :planned,
          "task",
          files: { "spec.md" => "---\nlane: quick\n---\n#{spec_body}", "plan.md" => "## U1\n" }
      end
      expect(described_class.target(subject_plan)).to be_nil
    end
  end

  describe ".advance" do
    it "reports the move without writing on a dry run" do
      plan_with("lane: quick")
      expect([described_class.advance(subject_plan, commit: false), subject_plan.file?("plan.md")])
        .to eq([%i[new planned], false])
    end

    it "writes a blank plan.md and moves a plan-lane plan to 📋" do
      plan_with("lane: plan")
      described_class.advance(subject_plan, commit: true)
      expect([subject_plan.status.key, subject_plan.read("plan.md")]).to eq([:ready_for_planning, ""])
    end

    it "carries the completion criteria into the plan it writes" do
      plan_with("lane: quick\ntask-completed-when: it works\nhow-to-verify: run it")
      described_class.advance(subject_plan, commit: true)
      expect(subject_plan.read("plan.md")).to include("## Task", "## Task completed when\n\n- it works", "## How to test\n\n- run it")
    end

    it "keeps a plan.md the author already wrote" do
      plans do |t|
        t.plan "001.00", :new, "task", files: { "spec.md" => "---\nlane: quick\n---\n#{spec_body}", "plan.md" => "## Mine\n" }
      end
      described_class.advance(subject_plan, commit: true)
      expect(subject_plan.read("plan.md")).to eq("## Mine\n")
    end
  end
end
