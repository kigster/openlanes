# frozen_string_literal: true

# C3: a project's active lessons are mirrored into the operator's global
# store as candidates tagged with the project, and a lesson two projects
# hold turns active there, under a global id.
RSpec.describe OpenLanes::Memory::Mirror do
  let(:home) { Dir.mktmpdir("global-memory") }
  let(:lessons_dir) { home }
  let(:inbox_dir) { File.join(home, "inbox") }
  let(:projects) { Hash.new { |hash, key| hash[key] = Dir.mktmpdir(key.tr("/", "-")) } }
  let(:today) { Date.new(2026, 11, 20) }
  let(:specs_lesson) { ["L-0001-real-trees", lesson_meta("L-0001", title: "Specs build real trees", source: [{ "plan" => "045.00", "finding" => "F1" }])] }

  after { FileUtils.rm_rf([home, *projects.values]) }

  # A project's lessons as a plain folder: the mirror takes any source with entries.
  def project(key, *lessons)
    dir = projects[key]
    lessons.each { |name, meta| write_lesson(dir, name, meta) }
    OpenLanes::Memory::Folder.new(name: :project, dir:)
  end

  def mirror(key, source) = described_class.new(project: key, source:, store: OpenLanes::Memory::GlobalStore.new(lessons_dir:, inbox_dir:), today: -> { today }).call

  def candidates = OpenLanes::Memory::Inbox.new(dir: inbox_dir).candidates
  def actives = OpenLanes::Memory::Inbox.new(dir: lessons_dir).candidates

  it "files an active project lesson as a global candidate, tagged with its project" do
    changes = mirror("github.com/a/one", project("github.com/a/one", specs_lesson))

    aggregate_failures do
      expect(changes.map { [it.kind, it.slug] }).to eq([[:candidate, "real-trees"]])
      expect(candidates.map(&:slug)).to eq(["real-trees"])
      expect(candidates.first.meta).to include("status" => "candidate",
        "title" => "Specs build real trees",
        "projects" => [{ "project" => "github.com/a/one", "lesson" => "L-0001" }])
      expect(actives).to be_empty
    end
  end

  it "is idempotent: the same project mirrored again changes nothing" do
    source = project("github.com/a/one", specs_lesson)
    mirror("github.com/a/one", source)
    before = File.read(candidates.first.path)

    expect(mirror("github.com/a/one", source).map(&:kind)).to eq([:known])
    expect(File.read(candidates.first.path)).to eq(before)
  end

  it "turns a lesson active, under a global id, once a second project holds it" do
    mirror("github.com/a/one", project("github.com/a/one", specs_lesson))
    changes = mirror("github.com/b/two", project("github.com/b/two", ["L-0009-real-trees", lesson_meta("L-0009", title: "Specs build real trees")]))
    library = OpenLanes::Memory::Library.load([OpenLanes::Memory::Folder.new(name: :global, dir: lessons_dir)])

    aggregate_failures do
      expect(changes.map { [it.kind, it.id] }).to eq([[:activate, "G-0001"]])
      expect(candidates).to be_empty
      expect(actives.map(&:slug)).to eq(["G-0001-real-trees"])
      expect(actives.first.meta["projects"].map { it["project"] }).to eq(%w[github.com/a/one github.com/b/two])
      expect(library.lessons).to contain_exactly(have_attributes(id: "G-0001", status: :active, scope: :global, confirmations: 1))
      expect(library.problems).to eq([])
    end
  end

  it "matches the same lesson by title when the projects named it differently" do
    mirror("github.com/a/one", project("github.com/a/one", specs_lesson))
    changes = mirror("github.com/b/two", project("github.com/b/two", ["L-0003-no-fake-fs", lesson_meta("L-0003", title: "specs build REAL trees.")]))

    expect(changes.map(&:kind)).to eq([:activate])
  end

  it "adds a third project to a lesson already active, and mints no second id" do
    mirror("github.com/a/one", project("github.com/a/one", specs_lesson))
    mirror("github.com/b/two", project("github.com/b/two", ["L-0009-real-trees", lesson_meta("L-0009", title: "Specs build real trees")]))
    changes = mirror("github.com/c/three", project("github.com/c/three", ["L-0002-real-trees", lesson_meta("L-0002", title: "Specs build real trees")]))

    expect(changes.map { [it.kind, it.id] }).to eq([[:joined, "G-0001"]])
    expect(actives.first.meta["projects"].size).to eq(3)
  end

  it "numbers global lessons past the highest one there" do
    write_lesson(lessons_dir, "G-0007-older", lesson_meta("G-0007"))
    mirror("github.com/a/one", project("github.com/a/one", specs_lesson))

    expect(mirror("github.com/b/two", project("github.com/b/two", ["real-trees", lesson_meta("L-1", title: "Specs build real trees")])).first.id)
      .to eq("G-0008")
  end

  # Two projects' `L-1.md` are unrelated lessons that share an id, not a slug.
  it "slugs a file named only by its id from its title" do
    changes = mirror("github.com/a/one", project("github.com/a/one", ["L-1", lesson_meta("L-1", title: "Run the linter first")]))
    other = mirror("github.com/b/two", project("github.com/b/two", ["L-1", lesson_meta("L-1", title: "Pin the Ruby version")]))

    expect([changes, other].flatten.map { [it.kind, it.slug] }).to eq([[:candidate, "run-the-linter-first"], [:candidate, "pin-the-ruby-version"]])
  end

  it "leaves a global lesson the operator wrote by hand alone" do
    hand = write_lesson(lessons_dir, "G-0001-mine", lesson_meta("G-0001", title: "Specs build real trees"))
    before = File.read(hand)
    mirror("github.com/a/one", project("github.com/a/one", specs_lesson))

    expect([File.read(hand), candidates.map(&:slug)]).to eq([before, ["real-trees"]])
  end

  it "mirrors only active lessons" do
    source = project("github.com/a/one",
      ["L-0001-waits", lesson_meta("L-0001", status: "candidate")],
      ["L-0002-gone", lesson_meta("L-0002", status: "retired")])

    expect([mirror("github.com/a/one", source), candidates]).to eq([[], []])
  end

  it "refuses a lesson that looks like it holds a secret" do
    source = project("github.com/a/one", ["L-0001-leaky", lesson_meta("L-0001", title: "Use token ghp_#{"a" * 36}")])

    expect(mirror("github.com/a/one", source).map(&:kind)).to eq([:refuse])
    expect(candidates).to be_empty
  end

  it "leaves no temporary file behind" do
    mirror("github.com/a/one", project("github.com/a/one", specs_lesson))

    expect(Dir.children(inbox_dir).sort).to eq([".lock", "real-trees.md"])
  end

  # Two runs in two projects finishing at once: the lock serialises them, so
  # neither reads the store before the other has written it.
  it "lands both projects when two mirror at once" do
    sources = { "github.com/a/one" => project("github.com/a/one", specs_lesson),
                "github.com/b/two" => project("github.com/b/two", ["L-0009-real-trees", lesson_meta("L-0009", title: "Specs build real trees")]) }
    sources.map { |key, source| Thread.new { mirror(key, source) } }.each(&:join)

    expect([candidates, actives.map(&:slug)]).to eq([[], ["G-0001-real-trees"]])
  end
end
