# frozen_string_literal: true

# A lesson is read from a person's markdown, so the cases worth pinning are
# the ones a person gets wrong: a missing key, a misspelt choice, a bad date.
# Each must name the file and the key, because the alternative is a lesson
# that silently never reaches a prompt.
RSpec.describe OpenLanes::Memory::Lesson do
  let(:dir) { Dir.mktmpdir("lessons") }
  let(:coder) { OpenLanes::Agents.find("backend-coder") }
  let(:reviewer) { OpenLanes::Agents.find("staff-reviewer") }

  after { FileUtils.rm_rf(dir) }

  def read(meta) = described_class.read(write_lesson(dir, "lesson", meta), scope: :project)

  it "reads every field, and defaults the ones a person may leave out" do
    lesson = read(lesson_meta("L-0001", checked_by: ["staff-reviewer"], confirmed: Date.new(2026, 11, 7)))

    expect(lesson).to have_attributes(id: "L-0001",
      title: "Lesson L-0001",
      applies_to: ["build"],
      checked_by: ["staff-reviewer"],
      kind: :practice,
      severity: :medium,
      status: :active,
      confirmed: Date.new(2026, 11, 7),
      scope: :project)
  end

  it "reads a quoted date as a date" do
    expect(read(lesson_meta("L-0001", confirmed: "2026-11-07")).confirmed).to eq(Date.new(2026, 11, 7))
  end

  {
    "id"         => "`id:` is missing",
    "title"      => "`title:` is missing",
    "applies_to" => "`applies_to:` names no agent or phase"
  }.each do |key, message|
    it "refuses a lesson without #{key}, naming the file" do
      meta = lesson_meta("L-0001").except(key)
      expect { read(meta) }.to raise_error(described_class::Invalid, /lesson\.md: #{Regexp.escape(message)}/)
    end
  end

  it "refuses a choice outside its list, saying which are allowed" do
    expect { read(lesson_meta("L-0001", severity: "urgent")) }
      .to raise_error(described_class::Invalid, /`severity: urgent` is not one of high, medium, low/)
  end

  it "refuses a date it cannot read" do
    expect { read(lesson_meta("L-0001", confirmed: "last tuesday")) }
      .to raise_error(described_class::Invalid, /`confirmed: last tuesday` is not a date/)
  end

  it "refuses frontmatter that is not YAML" do
    path = File.join(dir, "broken.md")
    File.write(path, "---\nid: [unclosed\n---\n")
    expect { described_class.read(path, scope: :project) }.to raise_error(described_class::Invalid, /not valid YAML/)
  end

  describe "who it is for" do
    it "matches an agent by name or by phase" do
      expect(read(lesson_meta("L-1", applies_to: ["backend-coder"]))).to be_for(coder)
      expect(read(lesson_meta("L-2", applies_to: ["build"]))).to be_for(coder)
      expect(read(lesson_meta("L-3", applies_to: ["build"]))).not_to be_for(reviewer)
    end

    it "matches every agent with `all`" do
      lesson = read(lesson_meta("L-1", applies_to: ["all"]))
      expect([lesson.for?(coder), lesson.for?(reviewer)]).to eq([true, true])
    end

    it "tells a checker apart from a follower" do
      lesson = read(lesson_meta("L-1", checked_by: ["review"]))
      expect([lesson.checked_by?(reviewer), lesson.checked_by?(coder), lesson.for?(reviewer)]).to eq([true, false, false])
    end
  end
end
