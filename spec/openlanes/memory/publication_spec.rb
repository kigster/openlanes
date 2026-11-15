# frozen_string_literal: true

# Promotion, delivered as a pull request: a real repository with a bare
# origin, a real inbox, and only the pull request's opener doubled.
RSpec.describe OpenLanes::Memory::Publication do
  subject(:publication) { described_class.new(root:, publisher:, base: "main", today: -> { Date.new(2026, 11, 13) }) }

  let(:root) { Dir.mktmpdir("memory-root") }
  let(:origin) { Dir.mktmpdir("memory-origin") }
  let(:fake_key) { "sk-ant-api03-#{"Qw7Er6Ty" * 6}" }
  let(:opened) { [] }
  let(:publisher) do
    double = Object.new
    sink = opened
    double.define_singleton_method(:publish_memory) do |checkout:, title:, body:|
      out = lambda { |*args|
        Open3.capture2e("git", "-C", checkout.path, "-c", "user.name=T", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", *args)
      }
      out.call("add", "--", ".openlanes/memory")
      out.call("commit", "-q", "-m", title, "--", ".openlanes/memory")
      files = out.call("show", "--name-only", "--format=", "HEAD").first.lines.map(&:strip)
      sink << { branch: checkout.branch, title:, body:, files: }
      OpenLanes::Vcs::Publisher::Publication.new(ordinal: nil, branch: checkout.branch, title:, url: "https://example.com/pr/1", refusal: nil)
    end
    double
  end

  def proposal(slug, body: "They race on one client.")
    OpenLanes::Memory::Proposal.new(slug:,
      title: "Run #{slug} alone",
      applies_to: ["staff-reviewer"],
      checked_by: [],
      kind: "pitfall",
      severity: "high",
      finding: "F1 flapping spec",
      body:)
  end

  def every_file = Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).reject { it.include?("/.git/") }.select { File.file?(it) }

  before do
    lessons_git(origin, "init", "-q", "--bare", "-b", "main")
    lessons_git(root, "init", "-q", "-b", "main")
    File.write(File.join(root, "README.md"), "x\n")
    lessons_git(root, "add", "-A")
    lessons_git(root, "commit", "-q", "-m", "init")
    lessons_git(root, "remote", "add", "origin", origin)
    lessons_git(root, "push", "-q", "origin", "main")
    lessons_git(root, "fetch", "-q", "origin")
  end

  after { FileUtils.rm_rf([root, origin]) }

  it "opens one pull request touching only .openlanes/memory, naming the lesson's evidence" do
    inbox = OpenLanes::Memory.inbox(root:)
    inbox.add(proposal("redis-specs"), plan: "001.00")
    inbox.add(proposal("redis-specs"), plan: "002.00")

    result = publication.call

    expect(result.branch).to eq("memory/2026-11-13-redis-specs")
    expect(opened.size).to eq(1)
    expect(opened.first[:files]).to all(start_with(".openlanes/memory/"))
    expect(opened.first[:files]).to include(".openlanes/memory/lessons/L-0001-redis-specs.md")
    expect(opened.first[:body]).to include("L-0001", "001.00", "002.00")
  end

  it "holds back a candidate approved by a person when it carries a key, and prints the value nowhere" do
    dir = File.join(root, OpenLanes::Memory::INBOX_DIR)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "leaky.md"),
      "---\nid: leaky\ntitle: Leaky\napplies_to: [build]\nstatus: candidate\napproved: true\n" \
      "source: [{plan: '001.00', finding: f}]\n---\n\nUse #{fake_key}\n")

    result = nil
    expect { result = publication.call }.not_to output(/#{fake_key}/o).to_stdout
    expect(result.changes.map(&:kind)).to eq([:refuse])
    expect(opened).to eq([])
    expect(result.changes.map(&:why).join).not_to include(fake_key)
  end

  it "opens nothing when nothing is ready" do
    OpenLanes::Memory.inbox(root:).add(proposal("once"), plan: "001.00")

    expect(publication.call).to have_attributes(branch: nil, url: nil)
    expect(opened).to eq([])
  end

  it "leaves the root inbox alone until the pull request is open, so a failed publish loses nothing" do
    inbox = OpenLanes::Memory.inbox(root:)
    inbox.add(proposal("redis-specs"), plan: "001.00")
    inbox.add(proposal("redis-specs"), plan: "002.00")
    failing = Object.new
    failing.define_singleton_method(:publish_memory) { |**| raise OpenLanes::Error, "gh: not logged in" }

    expect { described_class.new(root:, publisher: failing, base: "main").call }.to raise_error(OpenLanes::Error, /not logged in/)
    expect(inbox.candidates.map(&:slug)).to eq(["redis-specs"])
    expect(Dir.glob(File.join(root, OpenLanes::Memory::PROJECT_DIR, "*"))).to eq([])
  end

  it "takes a promoted candidate out of the root inbox once the pull request is open" do
    inbox = OpenLanes::Memory.inbox(root:)
    inbox.add(proposal("redis-specs"), plan: "001.00")
    inbox.add(proposal("redis-specs"), plan: "002.00")

    publication.call

    expect(inbox.candidates).to eq([])
  end

  it "never deletes a lesson already on the default branch, even one the scan flags" do
    lessons = File.join(root, OpenLanes::Memory::PROJECT_DIR)
    FileUtils.mkdir_p(lessons)
    File.write(File.join(lessons, "L-0003-old.md"),
      "---\nid: L-0003\ntitle: Old\napplies_to: [build]\nstatus: active\n---\n\nUse #{fake_key}\n")
    lessons_git(root, "add", "-A")
    lessons_git(root, "commit", "-q", "-m", "old lesson")
    lessons_git(root, "push", "-q", "origin", "main")
    lessons_git(root, "fetch", "-q", "origin")
    inbox = OpenLanes::Memory.inbox(root:)
    inbox.add(proposal("redis-specs"), plan: "001.00")
    inbox.add(proposal("redis-specs"), plan: "002.00")

    result = publication.call

    expect(opened.first[:files]).not_to include(".openlanes/memory/lessons/L-0003-old.md")
    expect(result.held_back).to eq([])
  end
end
