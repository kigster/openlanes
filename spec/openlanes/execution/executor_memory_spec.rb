# frozen_string_literal: true

# Lessons reach an agent through its prompt, read from the project's own
# checkout on every invocation; `--no-memory` keeps them out entirely.
RSpec.describe OpenLanes::Execution::Executor, :tree do
  let(:root) { File.dirname(plans_root) }
  let(:spawn) { ->(*, **) { raise "never spawned" } }
  let(:agent) { OpenLanes::Agents.find("spec-writer") }
  let(:subject_plan) { OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first }

  before do
    plans { |t| t.plan "000.00", :new, "a-feature", files: { "spec.md" => spec_body } }
    write_lesson(File.join(root, OpenLanes::Memory::PROJECT_DIR),
      "L-0007",
      lesson_meta("L-0007", title: "Name the reader in every spec", applies_to: ["spec-writer"]))
  end

  after { OpenLanes::Execution::Control.reset! }

  def prompt(**) = described_class.new(root:, spawn:, **).invocation(agent, subject_plan)[2]

  it "puts the agent's lessons in its prompt" do
    expect(prompt).to include("## Lessons from earlier plans", "L-0007 (medium) Name the reader in every spec")
  end

  it "reads a lesson written after the executor was built, as a long `start` needs" do
    executor = described_class.new(root:, spawn:)
    write_lesson(File.join(root, OpenLanes::Memory::PROJECT_DIR), "L-0008", lesson_meta("L-0008", applies_to: ["all"]))

    expect(executor.invocation(agent, subject_plan)[2]).to include("L-0008")
  end

  it "leaves the section out with memory: false" do
    expect(prompt(memory: false)).not_to include("Lessons from earlier plans", "L-0007")
  end
end
