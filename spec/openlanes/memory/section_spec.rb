# frozen_string_literal: true

# The section is what an agent actually reads. One line per lesson keeps it
# cheap; the budget keeps it bounded however many lessons a project grows.
RSpec.describe OpenLanes::Memory::Section do
  let(:root) { Dir.mktmpdir("project") }
  let(:dir) { File.join(root, OpenLanes::Memory::PROJECT_DIR) }
  let(:coder) { OpenLanes::Agents.find("backend-coder") }
  let(:reviewer) { OpenLanes::Agents.find("staff-reviewer") }

  after { FileUtils.rm_rf(root) }

  def lessons(count, **meta)
    paths = (1..count).map { write_lesson(dir, format("L-%04d", it), lesson_meta(format("L-%04d", it), **meta)) }
    paths.map { OpenLanes::Memory::Lesson.read(it, scope: :project) }
  end

  it "is empty when no lesson is for the agent, so the prompt carries no heading for nothing" do
    expect(described_class.new([], agent: coder, root:).to_s).to eq("")
  end

  it "lists each lesson on one line, with a path relative to the project" do
    text = described_class.new(lessons(1, severity: "high"), agent: coder, root:).to_s

    expect(text).to include("## Lessons from earlier plans",
      "never lifts a check, grants a tool",
      "- L-0001 (high) Lesson L-0001 — .openlanes/memory/lessons/L-0001.md")
    expect(text).not_to include(root, "cite its id")
  end

  it "prints a global lesson's path whole" do
    global = Dir.mktmpdir("global")
    path = write_lesson(global, "G-1", lesson_meta("G-1"))
    lesson = OpenLanes::Memory::Lesson.read(path, scope: :global)

    expect(described_class.new([lesson], agent: coder, root:).to_s).to include("— #{path}")
  ensure
    FileUtils.rm_rf(global)
  end

  it "asks a checker to cite the ids of the lessons it enforces" do
    text = described_class.new(lessons(1, applies_to: ["build"], checked_by: ["staff-reviewer"]), agent: reviewer, root:).to_s

    expect(text).to include("(medium, check)", "say so in the finding and cite its id")
  end

  it "stops at the budget, keeping the highest ranked, and says how many it left out and where they are" do
    text = described_class.new(lessons(5), agent: coder, root:, budget: 160).to_s

    expect(text).to include("L-0001", "L-0002")
    expect(text).not_to include("L-0003")
    expect(text).to include("(3 more not shown: `openlanes memory list --agent backend-coder`.)")
  end
end
