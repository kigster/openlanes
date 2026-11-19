# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::PlanState::Recovery, :tree do
  subject(:section) { described_class.new(document) }

  let(:document) { OpenLanes::Plans::PlanState::Document.new(dir: folder) }
  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => "# Work\n" } }
    path
  end
  let(:at) { Time.utc(2026, 11, 17, 9, 0, 0) }

  let(:stage) { { "agent" => "backend-coder", "round" => 1, "session" => "s1", "started_at" => at.iso8601, "cwd" => "/repo" } }

  def stages(*records) = document.update { it["stages"].concat(records) }

  it "starts fresh when no stage names a session" do
    expect(section.resumption("backend-coder", :building, "/repo", nil).reason).to eq("no session recorded for backend-coder")
  end

  it "resumes a session that left the plan where it is, in this checkout, on this adapter" do
    stages(stage.merge("to" => "building", "adapter" => "claude"))
    expect(section.resumption("backend-coder", :building, "/repo", "claude").session).to eq("s1")
  end

  it "says why it will not resume, in the order the checks run" do
    stages(stage.merge("to" => "building", "adapter" => "codex"))
    reasons = [["/repo", "claude"], ["/elsewhere", nil]].map { |root, adapter| section.resumption("backend-coder", "building", root, adapter).reason }
    expect(reasons).to eq(["session s1 ran on codex, not claude", "session s1 ran in /repo, not /elsewhere"])
  end

  it "does not resume a round that never settled, or one after which the plan moved" do
    stages(stage, stage.merge("agent" => "other", "session" => nil, "to" => "review", "started_at" => (at + 1).iso8601))
    expect(section.resumption("backend-coder", "building", "/repo", nil).reason).to eq("round 1 (s1) never settled")
  end

  it "reports Started stages of a dead harness on this host, never its own" do
    run = { "host" => Socket.gethostname }
    stages({ "status" => "Started", "run" => run.merge("pid" => 1) }, { "status" => "Started", "run" => run.merge("pid" => 2) })
    expect(section.stranded(->(_) { false }, 2).map { it.dig("run", "pid") }).to eq([1])
  end

  it "knows a pid that is not a positive integer is not alive" do
    expect([described_class.alive?(nil), described_class.alive?(Process.pid)]).to eq([false, true])
  end
end
