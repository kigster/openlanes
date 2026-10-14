# frozen_string_literal: true

require_relative "../support/control_room_process"

# The integration proof for plan 004: a real `openlanes run` (engine plus its
# API server, two processes), a real Redis, and HTTP and SSE as the page reads
# them. Nothing is stubbed. One blocked plan keeps the engine busy with no
# agent to start.
RSpec.describe "the control room, end to end", :redis do
  let(:url) { ControlRoomProcess.redis_url(12) }
  let(:root) { ControlRoomProcess.checkout(Dir.mktmpdir("openlanes-control-room")) }
  let(:plans) { File.join(root, ".plans") }
  let(:room) { ControlRoomProcess.new(root: root, redis_url: url) }
  let(:blocked) { "## B1 Which queue?\n\nRedis streams or SQS. Recommend streams.\n" }

  around do |example|
    reason = ControlRoomProcess.unmet(url)
    skip reason if reason

    PlansFixture::Builder.new(plans).plan("003.00", :blocked, "queue-choice", files: { "blocked.md" => blocked })
    room.start_engine
    example.run
  ensure
    room&.stop_all
    FileUtils.rm_rf(root) if root
  end

  def plan_on(board, ordinal)
    rows = board.fetch("me")&.then { it.fetch("plans") + it.fetch("backlog") } || []
    rows.find { it["ordinal"] == ordinal }
  end

  def status_key(row) = row["status"].is_a?(Hash) ? row["status"]["key"] : row["status"]

  it "serves the built page at /" do
    response = room.get("/")

    expect(response).to be_a(Net::HTTPOK)
    expect(response.body).to eq(File.read(ControlRoomProcess::DIST))
  end

  it "streams a board that lists the fixture's plans" do
    stream = room.sse("/api/events")

    event = stream.wait_for(deadline: 15) { it.name == "board" && plan_on(it.data, "003.00") }

    expect(status_key(plan_on(event.data, "003.00"))).to eq("blocked")
  end

  it "carries a state change in the engine to the stream within one second" do
    stream = room.sse("/api/events")
    stream.wait_for(deadline: 15) { it.name == "board" && plan_on(it.data, "003.00") }
    from = Dir[File.join(plans, "003.00-*")].first
    to = File.join(plans,
      OpenLanes::Plans.plan_dirname("003.00",
        OpenLanes::Plans.status(:product_blocked),
        "queue-choice"))

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    File.rename(from, to)
    stream.wait_for(deadline: 5) { it.name == "board" && status_key(plan_on(it.data, "003.00") || {}) == "product_blocked" }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    # The engine reads the tree once a tick (1 s) and the server polls Redis
    # every 0.25 s, so a rename at the worst moment takes 1.25 s to reach the
    # page; measured runs land at 1.0 to 1.1 s. The bound allows that and no more.
    expect(elapsed).to be <= 1.5
  end

  # `hold` needs a running agent, and an agent costs money, so the command that
  # proves exactly-once is `hold_blocked`: it changes run state on the engine,
  # and a second delivery that applied it again would show twice in the reply.
  it "applies a command posted twice with one id once, and its reply reaches the stream" do
    stream = room.sse("/api/events")
    stream.wait_for(deadline: 15) { it.name == "board" && plan_on(it.data, "003.00") }
    command = { id: "hold-once-1", kind: "hold_blocked", plan: "003.00", payload: { question: "B1" } }

    first = room.post("/api/commands", command)
    second = room.post("/api/commands", command)
    replies = [1, 2].map { stream.wait_for(deadline: 10) { it.name == "reply" && it.data["id"] == "hold-once-1" } }

    expect([first.code, second.code]).to eq(%w[202 202])
    expect(replies.map(&:data)).to all(include("status" => "done"))
    expect(replies.map { it.data["at"] }.uniq.size).to eq(1)
    held = stream.wait_for(deadline: 10) { it.name == "board" && plan_on(it.data, "003.00")&.dig("questions", 0, "held") }
    expect(plan_on(held.data, "003.00")["questions"].size).to eq(1)
  end
end
