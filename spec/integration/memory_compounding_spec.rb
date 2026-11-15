# frozen_string_literal: true

# Two plans rejected for the same reason compound into one lesson: the
# curator proposes it twice, promotion makes it active on a memory branch,
# a person merges that, and the next reviewer is shown it. Real git, a bare
# origin, a real `.plans` tree; only the agent and the pull request opener
# are doubled.
RSpec.describe "memory compounding across plans", :tree do
  let(:root) { File.dirname(plans_root) }
  let(:origin) { Dir.mktmpdir("memory-origin") }
  let(:fake_key) { "sk-ant-api03-#{"Lm4Np5Qr" * 6}" }
  let(:opened) { [] }
  let(:reviewer) { OpenLanes::Agents.find("staff-reviewer") }
  let(:answer) do
    JSON.generate("lesson" => { "slug" => "redis-outage-specs", "title" => "Run the Redis outage specs alone", "applies_to" => ["staff-reviewer"],
                                "finding" => "F1 flapping Redis outage spec", "body" => "They race on one client." })
  end
  let(:result) { instance_double(OpenLanes::Execution::Executor::Result, ok: true, note: "Completed") }
  let(:executor) do
    lambda do |_agent, subject, root:, handle:|
      handle.trace = File.join(root, subject.feature.ordinal.to_s)
      result
    end
  end

  def curating(memory: true, said: answer)
    curation = OpenLanes::Memory::Curation.new(executor:, agent: OpenLanes::Agents.find("curator"), root:, answer: ->(_) { said })
    OpenLanes::Engine::Curating.new(curation:, memory:)
  end

  def subjects = OpenLanes::Plans::Tree.new(dir: plans_root).subjects

  # The real publisher, whose git runs for real; `gh` is the only seam.
  def publisher = OpenLanes::Vcs::Publisher.new(root:, command: MemoryFixture::GitOnly.new(opened), base: "main", dry_run: false)

  before do
    plans do |t|
      t.plan "001.00", :rejected, "first"
      t.plan "002.00", :rejected, "second"
    end
    lessons_git(origin, "init", "-q", "--bare", "-b", "main")
    lessons_git(root, "init", "-q", "-b", "main")
    lessons_git(root, "add", "-A")
    lessons_git(root, "commit", "-q", "--allow-empty", "-m", "init")
    lessons_git(root, "remote", "add", "origin", origin)
    lessons_git(root, "push", "-q", "origin", "main")
    lessons_git(root, "fetch", "-q", "origin")
  end

  after { FileUtils.rm_rf(origin) }

  it "turns one finding on two plans into one active lesson the next reviewer is shown" do
    curating.call(subjects)
    candidate = OpenLanes::Memory.inbox(root:).find("redis-outage-specs")
    expect(candidate.plans).to eq(%w[001.00 002.00])

    published = OpenLanes::Memory::Publication.new(root:, publisher:, base: "main").call
    expect(opened.size).to eq(1)
    expect(opened.first[:files].grep(%r{lessons/L-\d{4}-.*\.md\z})).to eq([".openlanes/memory/lessons/L-0001-redis-outage-specs.md"])
    expect(lessons_git(origin, "show", "#{published.branch}:.openlanes/memory/lessons/L-0001-redis-outage-specs.md")).to include("status: active")

    # A person merges the memory pull request.
    lessons_git(origin, "update-ref", "refs/heads/main", "refs/heads/#{published.branch}")
    lessons_git(root, "fetch", "-q", "origin")

    library = OpenLanes::Memory.library(root:, env: { "XDG_CONFIG_HOME" => Dir.mktmpdir("xdg") })
    expect(library.for(reviewer).map(&:id)).to eq(["L-0001"])
    expect(OpenLanes::Memory.section(agent: reviewer, library:)).to include("L-0001", "Run the Redis outage specs alone")

    ignored, = Open3.capture2("git", "-C", root, "status", "--short", "--ignored", ".openlanes")
    expect(ignored.lines.grep(/\A!!/)).to eq([])
  end

  it "leaves no file under .openlanes holding a key the curator repeated" do
    leaky = answer.sub("They race on one client.", "Use #{fake_key}.")
    curating(said: leaky).call(subjects)

    files = Dir.glob(File.join(root, ".openlanes", "**", "*"), File::FNM_DOTMATCH).select { File.file?(it) }
    expect(files.map { File.read(it) }.join).not_to include(fake_key)
  end

  it "writes no candidate and opens no pull request with memory off" do
    expect(curating(memory: false).call(subjects)).to eq([])
    OpenLanes::Memory::Publication.new(root:, publisher:, base: "main").call

    expect([File.exist?(File.join(root, OpenLanes::Memory::INBOX_DIR)), opened]).to eq([false, []])
  end
end
