# frozen_string_literal: true

# `openlanes memory list` is read-only. What it must get right is the stream
# split (the list on STDOUT, skipped files warned about on STDERR) and that
# `--agent` prints exactly what that agent's prompt carries.
RSpec.describe OpenLanes::CLI::Memory::List do
  subject(:command) { described_class.new }

  # A `.plans` directory makes it a project, so `Base` enters it rather than refusing.
  let(:root) { Dir.mktmpdir("project").tap { FileUtils.mkdir_p(File.join(it, ".plans")) } }
  let(:dir) { File.join(root, OpenLanes::Memory::PROJECT_DIR) }

  after { FileUtils.rm_rf(root) }

  def list(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = swapping_streams(out, err) { Dir.chdir(root) { command.call(**) } }
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  # @return [Integer] the exit status a refusal raised, else 0
  def swapping_streams(out, err)
    original = [$stdout, $stderr]
    $stdout, $stderr = out, err
    yield
    0
  rescue SystemExit => e
    e.status
  ensure
    $stdout, $stderr = original
  end

  it "says how to start when there are no lessons" do
    expect(list.first).to include("No lessons yet. Write one per file under .openlanes/memory/lessons/")
  end

  it "tabulates every lesson on STDOUT and warns about a bad file on STDERR" do
    write_lesson(dir, "L-0001", lesson_meta("L-0001", title: "Real trees", checked_by: ["staff-reviewer"]))
    write_lesson(dir, "L-bad", lesson_meta("L-0002").except("id"))

    out, err, = list
    expect(out.lines.first.split).to eq(%w[ID SCOPE STATUS SEVERITY FOR CHECKED_BY TITLE])
    expect(out).to match(/L-0001\s+project\s+active\s+medium\s+build\s+staff-reviewer\s+Real trees/)
    expect(err).to include("skipped", "L-bad.md")
    expect(out).not_to include("L-bad")
  end

  it "prints the section an agent's prompt carries" do
    write_lesson(dir, "L-0001", lesson_meta("L-0001", title: "Real trees"))

    expect(list(agent: "backend-coder").first).to include("## Lessons from earlier plans", "L-0001 (medium) Real trees")
  end

  it "says so when no lesson is for the agent" do
    write_lesson(dir, "L-0001", lesson_meta("L-0001"))

    expect(list(agent: "planner").first).to eq("No active lesson is for planner.\n")
  end

  it "refuses an agent that does not exist" do
    _, err, status = list(agent: "nobody")
    expect([status, err]).to match([64, include("No agent named nobody")])
  end
end
