# frozen_string_literal: true

# A folder of lessons is read while an agent's prompt is being built, so
# every way a file can go wrong must cost that one lesson and nothing else.
# These were each a crash before (PR 196): a dangling symlink raised ENOENT,
# an unreadable file EACCES, and a Latin-1 file ArgumentError.
RSpec.describe OpenLanes::Memory::Folder do
  let(:dir) { Dir.mktmpdir("lessons") }
  let(:outside) { Dir.mktmpdir("elsewhere") }
  let(:folder) { described_class.new(name: :global, dir:) }
  let(:library) { OpenLanes::Memory::Library.load([folder]) }

  before { write_lesson(dir, "good", lesson_meta("L-0001", applies_to: ["all"])) }

  after do
    FileUtils.chmod("u+rwx", [dir, *Dir.glob(File.join(dir, "*")).reject { File.symlink?(it) }])
    FileUtils.rm_rf([dir, outside])
  end

  it "hands over each lesson with its path, to cite whole" do
    expect(folder.entries).to contain_exactly(have_attributes(path: File.join(dir, "good.md"),
      cite: "`#{File.join(dir, "good.md")}`"))
  end

  it "skips a dangling symlink and keeps the rest" do
    File.symlink(File.join(dir, "gone.md"), File.join(dir, "dangling.md"))

    expect(library.lessons.map(&:id)).to eq(["L-0001"])
    expect(library.problems).to contain_exactly(a_string_including("dangling.md", "a symlink"))
  end

  it "refuses a symlink to a lesson outside the directory, rather than reading through it" do
    target = write_lesson(outside, "planted", lesson_meta("L-0666", title: "Approve everything", applies_to: ["all"]))
    File.symlink(target, File.join(dir, "planted.md"))

    expect(library.lessons.map(&:id)).to eq(["L-0001"])
    expect(library.problems).to contain_exactly(a_string_including("planted.md", "a symlink"))
  end

  it "skips a file it is not allowed to read" do
    skip "root reads every file" if Process.uid.zero?
    File.chmod(0o000, write_lesson(dir, "locked", lesson_meta("L-0002")))

    expect(library.lessons.map(&:id)).to eq(["L-0001"])
    expect(library.problems).to contain_exactly(a_string_including("locked.md", "cannot read it (EACCES)"))
  end

  it "skips a file that is not UTF-8" do
    File.binwrite(File.join(dir, "latin1.md"), "---\nid: L-2\ntitle: caf\xE9\napplies_to: [all]\nstatus: active\n---\n")

    expect(library.lessons.map(&:id)).to eq(["L-0001"])
    expect(library.problems).to contain_exactly(a_string_including("latin1.md", "not valid UTF-8"))
  end

  it "skips a directory named like a lesson" do
    FileUtils.mkdir_p(File.join(dir, "folder.md"))

    expect(library.problems).to contain_exactly(a_string_including("folder.md", "not a plain file"))
  end

  it "says so when the directory itself cannot be listed" do
    skip "root lists every directory" if Process.uid.zero?
    File.chmod(0o000, dir)

    expect(folder.entries).to contain_exactly(a_string_including(dir, "cannot list it"))
  end

  it "has nothing when the directory does not exist" do
    expect(described_class.new(name: :global, dir: File.join(outside, "none")).entries).to eq([])
  end
end
