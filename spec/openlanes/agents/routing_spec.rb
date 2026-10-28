# frozen_string_literal: true

RSpec.describe OpenLanes::Agents::Routing, :tree do
  let(:agents) { OpenLanes::Agents.registry }
  let(:subject_plan) { OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first }
  let(:planned) { OpenLanes::Plans.status(:planned) }

  def plan_with(files)
    plans { |t| t.plan "001.00", :planned, "work", files: { "spec.md" => spec_body, "plan.md" => "## U1\n" }.merge(files) }
  end

  def routed = described_class.filter(agents.for_status(planned), subject_plan).map(&:name)

  it "gives a full-lane plan with front-end units to the pair" do
    plan_with("plan-frontend.md" => "# FE\n\n## F1\n")
    expect(routed).to eq(%w[backend-coder frontend-coder])
  end

  it "does not count a title line as a front-end unit" do
    plan_with("plan-frontend.md" => "# FE\n\nNo front-end units.\n")
    expect(routed).to eq(%w[backend-coder])
  end

  # Units live in plan.md since plan 003; the front end's are the `###`
  # headings under its `## Frontend`.
  describe "a plan.md with a ## Frontend section" do
    it "gives the pair a section that holds a unit" do
      plan_with("plan.md" => "# P\n\n## Backend\n\n### B1\n\n## Frontend\n\n### F1 Badge\n")
      expect(routed).to eq(%w[backend-coder frontend-coder])
    end

    it "starts nobody for a section that says there is no front end" do
      plan_with("plan.md" => "# P\n\n## Backend\n\n### B1\n\n## Frontend\n\nNone.\n\n## Order\n\n### Wave 1\n")
      expect(routed).to eq(%w[backend-coder])
    end

    it "matches the section name whatever its case" do
      plan_with("plan.md" => "## FRONTEND ##\n\n### F1\n")
      expect(routed).to eq(%w[backend-coder frontend-coder])
    end

    it "prefers the section to a legacy plan-frontend.md" do
      plan_with("plan.md" => "## Frontend\n\nNone.\n", "plan-frontend.md" => "## F1\n")
      expect(routed).to eq(%w[backend-coder])
    end

    it "reads a legacy plan-frontend.md when plan.md has no such section" do
      plan_with("plan.md" => "# P\n\n## U1\n", "plan-frontend.md" => "## F1\n")
      expect(routed).to eq(%w[backend-coder frontend-coder])
    end
  end

  it "gives a quick-lane plan to chores-coder alone" do
    plan_with("spec.md" => "---\nstarts: building\n---\n#{spec_body}")
    expect(routed).to eq(%w[chores-coder])
  end

  it "lets a lone candidate through whatever its needs say" do
    plan_with({})
    expect(described_class.filter([agents.find("frontend-coder")], subject_plan).map(&:name)).to eq(%w[frontend-coder])
  end

  it "answers for one agent" do
    plan_with("spec.md" => "---\nfrontend: false\n---\n#{spec_body}")
    expect(described_class.allows?(agents.find("frontend-coder"), subject_plan)).to be(false)
  end

  # The project says once what most plans would otherwise each repeat.
  describe "the project's frontend: in .openlanes.yml" do
    let(:frontend_units) { { "plan-frontend.md" => "# FE\n\n## F1\n" } }

    before do
      root = File.dirname(plans_root)
      File.write(File.join(root, ".openlanes.yml"), "frontend: false\n")
      Dir.chdir(root)
    end

    it "keeps frontend-coder off a plan whose spec.md says nothing" do
      plan_with(frontend_units)
      expect(routed).to eq(%w[backend-coder])
    end

    it "yields to a spec.md that says otherwise" do
      plan_with(frontend_units.merge("spec.md" => "---\nfrontend: true\n---\n#{spec_body}"))
      expect(routed).to eq(%w[backend-coder frontend-coder])
    end
  end

  # staff-reviewer reads the pull request; with none open there is
  # nothing to review, so the plan waits at 🟢 for one.
  describe "a plan ready for review" do
    let(:ready) { OpenLanes::Plans.status(:ready_for_review) }

    def review_routed = described_class.filter(agents.for_status(ready), subject_plan).map(&:name)

    it "goes to all three reviewers once its pull request is open" do
      plans { |t| t.plan "001.00", :ready_for_review, "work", files: { "spec.md" => spec_body }, prs: [t.open(7, "[001.00] Work")] }
      expect(review_routed).to contain_exactly("staff-reviewer", "security-reviewer", "design-reviewer")
    end

    # Plan 031, V5: a plan that started at building gets one reviewer.
    it "goes to staff-reviewer alone when the plan started at building" do
      plans do |t|
        t.plan "001.00",
          :ready_for_review,
          "work",
          files: { "spec.md" => "---\nstarts: building\n---\n#{spec_body}" },
          prs:   [t.open(7, "[001.00] Work")]
      end
      expect(review_routed).to eq(%w[staff-reviewer])
    end

    it "waits, unassigned, while no pull request is open" do
      plans { |t| t.plan "001.00", :ready_for_review, "work", files: { "spec.md" => spec_body } }
      expect(review_routed).to be_empty
    end

    it "is not allowed to the reviewer with only a merged pull request" do
      plans { |t| t.plan "001.00", :ready_for_review, "work", files: { "spec.md" => spec_body }, prs: [t.merged(7, "[001.00] Work")] }
      expect(described_class.allows?(agents.find("staff-reviewer"), subject_plan)).to be(false)
    end
  end
end
