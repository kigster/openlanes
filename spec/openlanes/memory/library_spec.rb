# frozen_string_literal: true

# The library decides which lessons an agent sees and in what order. The
# order matters because the prompt's budget cuts from the bottom: what is
# ranked last is what an agent never hears.
RSpec.describe OpenLanes::Memory::Library do
  let(:project) { Dir.mktmpdir("project-lessons") }
  let(:global) { Dir.mktmpdir("global-lessons") }
  let(:scopes) do
    [OpenLanes::Memory::Folder.new(name: :project, dir: project), OpenLanes::Memory::Folder.new(name: :global, dir: global)]
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

  it "takes a source's own reasons for skipping a file as problems" do
    source = Data.define(:name, :entries).new(name: :project, entries: ["x.md: not a plain file"])

    expect(described_class.load([source])).to have_attributes(lessons: [], problems: ["x.md: not a plain file"])
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

    it "counts each plan in `source:` once as a confirmation" do
      sources = [{ "plan" => "001.00" }, { "plan" => "001.00", "finding" => "F2" }, { "plan" => "002.00" }, "not a map"]
      write_lesson(project, "a", lesson_meta("L-1", source: sources))

      expect(library.lessons.first.confirmations).to eq(2)
    end

    it "ranks the lesson more plans confirmed above a more severe one-off" do
      write_lesson(project, "a", lesson_meta("L-1", severity: "high", source: [{ "plan" => "001.00" }]))
      write_lesson(project, "b", lesson_meta("L-2", severity: "low", source: %w[001.00 002.00 003.00].map { { "plan" => it } }))

      expect(library.for(coder).map(&:id)).to eq(%w[L-2 L-1])
    end

    # An agent on its tenth plan: ten lessons from nine plans, one confirmed
    # by five of them. A budget that fits six keeps the five-plan lesson and
    # cuts the one-offs first; a retired lesson is never shown at all.
    it "shows a tenth-plan agent its own, its phase's and everyone's lessons, trimming one-offs first" do
      plans = (1..9).map { format("%03d.00", it) }
      write_lesson(project, "five", lesson_meta("L-0010", applies_to: ["backend-coder"], source: plans.first(5).map { { "plan" => it } }))
      write_lesson(project, "two", lesson_meta("L-0009", applies_to: ["all"], source: plans.last(2).map { { "plan" => it } }))
      (1..8).each do |n|
        audience = [%w[backend-coder], %w[build], %w[all]][n % 3]
        write_lesson(project, "one-#{n}", lesson_meta(format("L-%04d", n), applies_to: audience, source: [{ "plan" => plans[n] }]))
      end
      everyone = plans.map { { "plan" => it } }
      write_lesson(project, "retired", lesson_meta("L-0011", applies_to: ["all"], status: "retired", source: everyone))
      write_lesson(project, "elsewhere", lesson_meta("L-0012", applies_to: ["review"], source: everyone))

      ranked = library.for(coder)
      line = ->(lesson) { "- #{lesson.id} (#{lesson.severity}) #{lesson.title} — #{lesson.cite}".size + 1 }
      six = ranked.first(6).sum(&line)
      text = OpenLanes::Memory::Section.new(ranked, agent: coder, budget: six).to_s

      expect(ranked.map(&:id)).to eq(%w[L-0010 L-0009 L-0001 L-0002 L-0003 L-0004 L-0005 L-0006 L-0007 L-0008])
      expect(text).to include("L-0010", "L-0009", "(4 more not shown")
      expect(text).not_to include("L-0011", "L-0012", "L-0008")
    end
  end
end
