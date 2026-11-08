# frozen_string_literal: true

# The library decides which lessons an agent sees and in what order. The
# order matters because the prompt's budget cuts from the bottom: what is
# ranked last is what an agent never hears.
RSpec.describe OpenLanes::Memory::Library do
  let(:project) { Dir.mktmpdir("project-lessons") }
  let(:global) { Dir.mktmpdir("global-lessons") }
  let(:scopes) do
    [OpenLanes::Memory::Scope.new(name: :project, dir: project), OpenLanes::Memory::Scope.new(name: :global, dir: global)]
  end
  let(:library) { described_class.load(scopes) }
  let(:coder) { OpenLanes::Agents.find("backend-coder") }

  after { FileUtils.rm_rf([project, global]) }

  it "lets a project lesson shadow a global one with the same id" do
    write_lesson(project, "mine", lesson_meta("L-0001", title: "The project's"))
    write_lesson(global, "theirs", lesson_meta("L-0001", title: "The operator's"))

    expect(library.lessons.map { [it.title, it.scope] }).to eq([["The project's", :project]])
    expect(library.problems).to eq([])
  end

  it "reports a duplicate id inside one scope instead of picking by file order" do
    write_lesson(project, "a", lesson_meta("L-0001"))
    write_lesson(project, "b", lesson_meta("L-0001"))

    expect(library.lessons.size).to eq(1)
    expect(library.problems).to contain_exactly(a_string_including("b.md: id L-0001 is also", "a.md"))
  end

  it "skips a file it cannot read and keeps the rest" do
    write_lesson(project, "good", lesson_meta("L-0001"))
    write_lesson(project, "bad", lesson_meta("L-0002").except("title"))

    expect(library.lessons.map(&:id)).to eq(["L-0001"])
    expect(library.problems).to contain_exactly(a_string_including("bad.md", "`title:` is missing"))
  end

  it "is empty when neither directory exists" do
    FileUtils.rm_rf([project, global])
    expect(library).to have_attributes(lessons: [], problems: [])
  end

  describe "#for" do
    it "gives an agent only the active lessons it follows or checks" do
      write_lesson(project, "followed", lesson_meta("L-1", applies_to: ["backend-coder"]))
      write_lesson(project, "checked", lesson_meta("L-2", applies_to: ["frontend"], checked_by: ["build"]))
      write_lesson(project, "other", lesson_meta("L-3", applies_to: ["review"]))
      write_lesson(project, "candidate", lesson_meta("L-4", status: "candidate"))
      write_lesson(project, "graduated", lesson_meta("L-5", status: "graduated"))

      expect(library.for(coder).map(&:id)).to eq(%w[L-1 L-2])
    end

    it "ranks by severity, then the most recently confirmed, then id" do
      write_lesson(project, "a", lesson_meta("L-1", severity: "low"))
      write_lesson(project, "b", lesson_meta("L-2", severity: "high", confirmed: "2026-01-01"))
      write_lesson(project, "c", lesson_meta("L-3", severity: "high", confirmed: "2026-11-01"))
      write_lesson(project, "d", lesson_meta("L-4", severity: "high"))
      write_lesson(project, "e", lesson_meta("L-0", severity: "high"))

      expect(library.for(coder).map(&:id)).to eq(%w[L-3 L-2 L-0 L-4 L-1])
    end
  end
end
