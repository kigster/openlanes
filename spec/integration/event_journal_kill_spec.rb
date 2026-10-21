# frozen_string_literal: true

# B6: an engine SIGKILLed mid-run loses no event it acknowledged, and a
# replay rebuilds what was in flight from the file alone.
RSpec.describe "progress journal under SIGKILL" do
  let(:root) { Dir.mktmpdir("openlanes-kill-root") }

  after { FileUtils.rm_rf(root) }

  # The child: acknowledges each event's seq on the pipe once append returns.
  def append_until_killed(reader, writer)
    reader.close
    journal = OpenLanes::Engine::EventJournal.new(root:, run_id: "killed", node: "n")
    journal.append(:run_started, jobs: 1)
    journal.append(:agent_started,
      plan:        "039.00",
      agent:       "luke-backend",
      round:       1,
      pid:         Process.pid,
      started_at:  nil,
      session_id:  nil,
      output_file: "/t/trace.ndjson")
    journal.append(:agent_session, plan: "039.00", agent: "luke-backend", session_id: "s-1")
    offset = 0
    loop do
      offset += 64
      event = journal.append(:agent_offset, plan: "039.00", agent: "luke-backend", offset:)
      writer.puts(event["seq"])
      writer.flush
    end
  end

  it "replays every acknowledged event after the writer is killed" do
    FileUtils.mkdir_p(File.join(root, ".plans"))
    reader, writer = IO.pipe
    pid = fork { append_until_killed(reader, writer) }
    writer.close
    acked = Array.new(20) { reader.gets.to_i }
    Process.kill(:KILL, pid)
    Process.wait(pid)
    acked.concat(reader.read.split.map(&:to_i))
    reader.close

    path = File.join(OpenLanes::Runtime.journal_dir(root:), "killed.ndjson")
    picture = OpenLanes::Engine::EventJournal::Replay.call(path)
    expect(picture.seq).to be >= acked.max
    expect(picture).to be_running
    expect(picture.agents.map { [it.plan, it.pid, it.session_id, it.output_file] }).to eq([["039.00", pid, "s-1", "/t/trace.ndjson"]])
    expect(picture.agents.first.offset).to be >= (acked.max - 3) * 64
  end

  # A real engine: a Runner round over a real .plans tree, its one agent a
  # fake that names its pid, session and trace and then never returns.
  context "with an engine killed mid-round", :tree do
    # Not `root`: the outer after hook removes that, and here it is the fixture's.
    let(:project) { File.dirname(plans_root) }
    # let!, so the child inherits the parent's paths rather than minting its own.
    let!(:agents_dir) { Dir.mktmpdir }
    let!(:trace) { File.join(Dir.mktmpdir, "trace.ndjson") }

    after { FileUtils.rm_rf(agents_dir) }

    def run_engine
      $stderr.reopen(File::NULL)
      File.write(File.join(agents_dir, "leah.md"),
        "---\nname: leah-researcher\nhandles: [new]\nadvances_to: researched\nrounds: 1\n" \
        "adapter: claude\nledger: [spec.md]\n---\nbody")
      trace_file = trace
      executor = lambda { |_agent, _subject, handle:, **|
        handle.child = Struct.new(:pid).new(Process.pid)
        handle.trace = trace_file
        handle.session = "s-1"
        File.write(trace_file, "{}\n{}\n")
        sleep
      }
      OpenLanes::Engine::Runner.new(tree:      OpenLanes::Plans::Tree.new(dir: plans_root),
        executor:,
        agents:    OpenLanes::Agents::Registry.new(dir: agents_dir),
        isolation: :shared,
        jobs:      1,
        sleeper:   ->(_) { sleep 0.02 },
        journal:   OpenLanes::Engine::EventJournal.new(root: project, run_id: "engine", node: "n"),
        extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false)).call
    end

    it "replays the agent in flight and leaves nothing of its own under .plans" do
      plans { |t| t.plan "001.00", :new, "remember", files: { "spec.md" => spec_body } }
      path = File.join(OpenLanes::Runtime.journal_dir(root: project), "engine.ndjson")
      # exit!, so the child never runs the suite's at_exit hooks or cleanups.
      pid = fork do
        run_engine
      ensure
        exit!(1)
      end
      deadline = Time.now + 10
      sleep 0.02 until (File.exist?(path) && File.read(path).include?('"agent_offset"')) || Time.now > deadline
      Process.kill(:KILL, pid)
      Process.wait(pid)

      picture = OpenLanes::Engine::EventJournal::Replay.call(path)
      expect(picture).to be_running
      expect(picture.agents.map { [it.plan, it.agent, it.pid, it.session_id, it.output_file, it.offset] })
        .to eq([["001.00", "leah-researcher", pid, "s-1", trace, File.size(trace)]])
      expect(Dir.glob(File.join(plans_root, "**", "{*.ndjson,*.lock,*.tmp,openlanes-state.json}"))).to eq([])
    end
  end
end
