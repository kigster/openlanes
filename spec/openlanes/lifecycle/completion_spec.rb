# frozen_string_literal: true

RSpec.describe OpenLanes::Lifecycle::Completion, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:subject_plan) { tree.reload.subjects.first }
  let(:frontmatter) { "---\ntask-completed-when:\n  - the editor opens\nhow-to-verify:\n  - bundle exec rspec\n---\n" }
  let(:plan_text) { "# Plan\n\n## Unit 1\n" }

  before do
    plans do |t|
      t.plan "001.00",
        :ready_for_planning,
        "task",
        files: { "spec.md" => "#{frontmatter}#{spec_body}", "plan.md" => plan_text }
    end
  end

  describe ".copy" do
    it "appends both sections to a plan that lacks them" do
      described_class.copy(subject_plan)
      expect(subject_plan.read("plan.md")).to end_with(<<~MARKDOWN)
        ## Task completed when

        - the editor opens

        ## How to verify

        - bundle exec rspec
      MARKDOWN
    end

    context "when a check spans lines" do
      let(:frontmatter) { "---\nhow-to-verify: |\n  run the CLI\n  check its output\n---\n" }

      it "copies it as one item, its continuation indented under it" do
        described_class.copy(subject_plan)
        expect(subject_plan.read("plan.md")).to end_with("## How to verify\n\n- run the CLI\n  check its output\n")
      end
    end

    context "when resync dirs has moved how-to-verify: into the body (M10)" do
      let(:frontmatter) { "---\ntask-completed-when:\n  - the editor opens\n---\n" }
      let(:spec_text) { "#{frontmatter}#{spec_body}\n## How to tell it's working?\n\n- bundle exec rspec\n" }

      before { File.write(File.join(subject_plan.feature.path, "spec.md"), spec_text) }

      it "copies the checks from the section all the same" do
        described_class.copy(subject_plan)
        expect(subject_plan.read("plan.md")).to end_with("## How to verify\n\n- bundle exec rspec\n")
      end
    end

    # Prose is a check too, and a fenced block travels with its check: what
    # plan.md gets must read back as the same checks.
    context "when the section holds prose and a fenced block" do
      let(:frontmatter) { "" }
      let(:section) do
        "Open the board.\nIt shows the plan.\n\n- Run this:\n\n  ```bash\n  bin/setup\n\n  - not an item\n  ```\n"
      end
      let(:checks) { ["Open the board.\nIt shows the plan.", "Run this:\n```bash\nbin/setup\n\n- not an item\n```"] }

      before do
        File.write(File.join(subject_plan.feature.path, "spec.md"), "# T\n\n## How to tell it's working?\n\n#{section}")
      end

      it "writes each check as one item that reads back unchanged" do
        described_class.copy(subject_plan)
        copied = subject_plan.read("plan.md")[/^## How to verify\n.*/m]
        reread = OpenLanes::Plans::Spec.parse(copied.sub("## How to verify", "## How to tell it's working?"))

        aggregate_failures do
          expect(OpenLanes::Plans::Spec.parse("# T\n\n## How to tell it's working?\n\n#{section}").how_to_verify).to eq(checks)
          expect(reread.how_to_verify).to eq(checks)
        end
      end
    end

    it "keeps what the planner already wrote" do
      described_class.copy(subject_plan)
      expect(subject_plan.read("plan.md")).to start_with(plan_text)
    end

    it "reports that it changed the file" do
      expect(described_class.copy(subject_plan)).to be(true)
    end

    context "when the planner already wrote one section" do
      let(:plan_text) { "# Plan\n\n## Task completed when\n\nIn its own words.\n" }

      it "leaves that section alone and adds only the missing one" do
        described_class.copy(subject_plan)
        text = subject_plan.read("plan.md")
        expect(text.scan("## Task completed when").size).to eq(1)
        expect(text).to include("In its own words.", "## How to verify")
      end
    end

    it "is idempotent" do
      described_class.copy(subject_plan)
      expect { described_class.copy(subject_plan) }.not_to(change { subject_plan.read("plan.md") })
    end

    context "when the spec says nothing" do
      let(:frontmatter) { "" }

      it "writes nothing" do
        expect(described_class.copy(subject_plan)).to be(false)
      end
    end
  end
end
