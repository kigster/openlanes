# frozen_string_literal: true

RSpec.describe OpenLanes::Lifecycle::Lanes, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:subject_plan) { tree.reload.subjects.first }

  def plan_with(frontmatter, status: :new)
    plans { |t| t.plan "001.00", status, "task", files: { "spec.md" => "---\n#{frontmatter}\n---\n#{spec_body}" } }
  end

  describe ".target" do
    it "sends a starts: planning plan to 📋, where the planner answers depends_on" do
      plan_with("starts: planning")
      expect(described_class.target(subject_plan).key).to eq(:ready_for_planning)
    end

    it "sends a starts: building plan straight to ⭐️, so the planner never sees it" do
      plan_with("starts: building")
      expect(described_class.target(subject_plan).key).to eq(:planned)
    end

    it "sends a starts: building plan on from 📋 to ⭐️, past the planner" do
      plans do |t|
        t.plan "001.00",
          :ready_for_planning,
          "task",
          files: { "spec.md" => "---\nstarts: building\ndepends_on: [none]\n---\n#{spec_body}", "plan.md" => "" }
      end
      expect(described_class.target(subject_plan).key).to eq(:planned)
    end

    it "leaves a starts: planning plan at 📋 for the planner" do
      plans do |t|
        t.plan "001.00",
          :ready_for_planning,
          "task",
          files: { "spec.md" => "---\nstarts: planning\ndepends_on: [none]\n---\n#{spec_body}", "plan.md" => "" }
      end
      expect(described_class.target(subject_plan)).to be_nil
    end

    it "leaves a full-lane plan where it is" do
      plan_with("starts: research")
      expect(described_class.target(subject_plan)).to be_nil
    end

    it "leaves a plan that is already past the phases its lane skips" do
      plans do |t|
        t.plan "001.00",
          :planned,
          "task",
          files: { "spec.md" => "---\nstarts: building\n---\n#{spec_body}", "plan.md" => "## U1\n" }
      end
      expect(described_class.target(subject_plan)).to be_nil
    end
  end

  describe ".advance" do
    it "reports the move without writing on a dry run" do
      plan_with("starts: building")
      expect([described_class.advance(subject_plan, commit: false), subject_plan.file?("plan.md")])
        .to eq([%i[new planned], false])
    end

    it "writes a blank plan.md and moves a starts: planning plan to 📋" do
      plan_with("starts: planning")
      described_class.advance(subject_plan, commit: true)
      expect([subject_plan.status.key, subject_plan.read("plan.md")]).to eq([:ready_for_planning, ""])
    end

    it "writes the one-unit plan for a starts: building plan at 📋, criteria and all" do
      plans do |t|
        t.plan "001.00",
          :ready_for_planning,
          "task",
          files: { "spec.md" => "---\nstarts: building\ndepends_on: [none]\ntask-completed-when: it works\nhow-to-verify: run it\n---\n#{spec_body}",
                   "plan.md" => "" }
      end
      expect(described_class.advance(subject_plan, commit: true)).to eq(%i[ready_for_planning planned])
      expect(subject_plan.read("plan.md")).to include("## Task", "## Task completed when\n\n- it works", "## How to test\n\n- run it")
    end

    it "keeps a plan.md the author already wrote" do
      plans do |t|
        t.plan "001.00", :new, "task", files: { "spec.md" => "---\nstarts: building\n---\n#{spec_body}", "plan.md" => "## Mine\n" }
      end
      expect(described_class.advance(subject_plan, commit: true)).to eq(%i[new planned])
      expect(subject_plan.read("plan.md")).to eq("## Mine\n")
    end
  end
end
