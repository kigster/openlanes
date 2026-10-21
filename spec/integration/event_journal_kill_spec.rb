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
    expect(Dir.glob(File.join(root, ".plans", "**", "*"))).to be_empty
  end
end
