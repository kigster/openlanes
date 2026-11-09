# frozen_string_literal: true

# Project lessons are read from a commit, never from the working tree,
# because any agent with a shell can write the working tree and only a
# merge moves the default branch (PR 196).
RSpec.describe OpenLanes::Memory::Committed do
  let(:root) { Dir.mktmpdir("project") }
  let(:dir) { File.join(root, OpenLanes::Memory::PROJECT_DIR) }
  let(:source) { described_class.at(name: :project, root:, ref: "origin/main", dir: OpenLanes::Memory::PROJECT_DIR) }
  let(:library) { OpenLanes::Memory::Library.load([source]) }

  after { FileUtils.rm_rf(root) }

  it "reads the lessons the commit holds, and cites them at that commit" do
    write_lesson(dir, "L-0001", lesson_meta("L-0001"))
    sha = publish_lessons(root)

    expect(library.lessons).to contain_exactly(have_attributes(id: "L-0001",
      path: ".openlanes/memory/lessons/L-0001.md at #{sha[0, 7]}",
      cite: "`git show #{sha[0, 7]}:.openlanes/memory/lessons/L-0001.md`"))
  end

  it "ignores a lesson written into the checkout but never merged" do
    write_lesson(dir, "L-0001", lesson_meta("L-0001"))
    publish_lessons(root)
    write_lesson(dir, "L-0002", lesson_meta("L-0002", checked_by: ["staff-reviewer"]))
    File.write(File.join(dir, "L-0001.md"), File.read(File.join(dir, "L-0001.md")).sub("Lesson L-0001", "Rewritten"))

    expect(library.lessons.map { [it.id, it.title] }).to eq([["L-0001", "Lesson L-0001"]])
  end

  it "keeps reading the commit it was given after the branch moves" do
    write_lesson(dir, "L-0001", lesson_meta("L-0001"))
    publish_lessons(root)
    pinned = source
    write_lesson(dir, "L-0002", lesson_meta("L-0002"))
    publish_lessons(root)

    expect(OpenLanes::Memory::Library.load([pinned]).lessons.map(&:id)).to eq(["L-0001"])
  end

  it "skips a committed symlink" do
    write_lesson(dir, "L-0001", lesson_meta("L-0001"))
    File.symlink("/etc/hosts", File.join(dir, "hosts.md"))
    publish_lessons(root)

    expect(library.lessons.map(&:id)).to eq(["L-0001"])
    expect(library.problems).to contain_exactly(a_string_including("hosts.md", "not a plain file (mode 120000)"))
  end

  it "skips a file whose name holds a newline" do
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "two\nlines.md"), "---\nid: L-1\n---\n")
    publish_lessons(root)

    expect(library.problems).to contain_exactly(a_string_including("control character"))
  end

  it "is nil when the ref names no commit" do
    lessons_git(root, "init", "-q", "-b", "main")
    expect(source).to be_nil
  end

  it "has nothing when the commit has no lessons directory" do
    expect(described_class.at(name: :project, root: publish_lessons(root) && root, ref: "origin/main", dir: "none").entries)
      .to eq([])
  end
end
