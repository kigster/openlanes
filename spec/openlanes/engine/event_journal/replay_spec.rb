# frozen_string_literal: true

# B3: a journal replayed into what was in flight, torn last line included.
RSpec.describe OpenLanes::Engine::EventJournal::Replay do
  let(:root) { Dir.mktmpdir("openlanes-replay-root") }
  let(:journal) { OpenLanes::Engine::EventJournal.new(root:, run_id: "r1", node: "n") }
  let(:a) { { plan: "039.00", agent: "backend-coder" } }
  let(:b) { { plan: "040.00", agent: "frontend-coder" } }

  before do
    journal.append(:run_started, jobs: 2)
    journal.append(:transition, plan: "039.00", from: "planned", to: "building", event: "build")
    journal.append(:agent_started, **a, round: 1, pid: 11, started_at: nil, session_id: nil, output_file: "/t/a")
    journal.append(:agent_started, **b, round: 1, pid: 12, started_at: "2026-10-21T10:00:00Z", session_id: nil, output_file: "/t/b")
    journal.append(:agent_session, **a, session_id: "s-a")
    journal.append(:agent_offset, **a, offset: 512)
    journal.append(:agent_ended, **b, exit: 0)
    journal.close
  end

  after { FileUtils.rm_rf(root) }

  it "rebuilds the agents still running, with pid, session, output file and offset" do
    picture = described_class.call(journal.path)
    expect(picture.agents).to eq([described_class::Agent.new(plan: "039.00",
      agent: "backend-coder",
      round: 1,
      pid: 11,
      started_at: nil,
      session_id: "s-a",
      output_file: "/t/a",
      offset: 512)])
    expect(picture.plans).to eq("039.00" => "building")
    expect(picture).to be_running
    expect(picture.seq).to eq(7)
  end

  it "tolerates a line torn mid-write by a kill" do
    File.open(journal.path, "a") { it.write('{"v":1,"seq":8,"kind":"agent_off') }
    picture = described_class.call(journal.path)
    expect([picture.torn, picture.agents.map(&:offset)]).to eq([1, [512]])
  end

  it "skips a line from a newer schema rather than guessing at it" do
    File.open(journal.path, "a") { it.puts(JSON.generate("v" => 99, "seq" => 8, "kind" => "agent_ended", **a.transform_keys(&:to_s))) }
    picture = described_class.call(journal.path)
    expect([picture.newer, picture.agents.size]).to eq([1, 1])
  end

  it "knows a run that ended" do
    File.open(journal.path, "a") { it.puts(JSON.generate("v" => 1, "seq" => 8, "kind" => "run_ended")) }
    expect(described_class.call(journal.path)).not_to be_running
  end

  it "ignores a session or offset for an agent it never saw start" do
    File.open(journal.path, "a") { it.puts(JSON.generate("v" => 1, "seq" => 8, "kind" => "agent_offset", "plan" => "1", "agent" => "x", "offset" => 3)) }
    expect(described_class.call(journal.path).agents.size).to eq(1)
  end
end
