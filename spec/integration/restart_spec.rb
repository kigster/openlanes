# frozen_string_literal: true

require_relative "../support/control_room_process"

# Plan 004, B3: either process dies with `kill -9` and nothing a person did is
# lost. The API server holds no state, so a new one picks up the replies a page
# missed from Redis; the engine's run state survives in two copies, and a
# command posted while no engine ran waits in its stream to be applied once.
RSpec.describe "the control room across a restart", :redis do
  let(:url) { ControlRoomProcess.redis_url(11) }
  let(:root) { ControlRoomProcess.checkout(Dir.mktmpdir("openlanes-restart")) }
  let(:plans) { File.join(root, ".plans") }
  let(:room) { ControlRoomProcess.new(root: root, redis_url: url) }
  let(:blocked) do
    "## B1 Which queue?\n\nRedis streams or SQS. Recommend streams.\n\n" \
      "## B2 Which region?\n\nOne or two. Recommend one.\n"
  end

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

  def plan_on(board)
    rows = board.fetch("me")&.then { it.fetch("plans") + it.fetch("backlog") } || []
    rows.find { it["ordinal"] == "003.00" }
  end

  # @return [Array<Boolean>] B1's and B2's held flags, as the page draws them
  def held(board) = plan_on(board)&.fetch("questions", nil)&.map { it["held"] }

  def hold(question) = { id: "hold-#{question}", kind: "hold_blocked", plan: "003.00", payload: { question: } }

  def live_state = JSON.parse(File.read(File.join(plans, "openlanes-state.json"))).fetch("live", {})

  it "replays to a reconnecting page what it missed while the API server was down" do
    first = room.sse("/api/events")
    cursor = first.wait_for(deadline: 15) { it.name == "cursor" }.id
    first.wait_for(deadline: 15) { it.name == "board" && plan_on(it.data) }
    first.close

    # Applied while no page listens, then the server dies before any page could hear of it.
    expect(room.post("/api/commands", hold("B1")).code).to eq("202")
    room.wait_until(deadline: 10) { held(JSON.parse(room.get("/api/board").body))&.first }
    room.kill(:server)
    room.start_server

    # Both come on the stream's first look, the board before the replies.
    # Taken in whichever order they arrive: the engine is idle by now, so it
    # nudges no second board, and waiting for one after the reply would
    # wait for the next ping.
    again = room.sse("/api/events", last_event_id: cursor)
    seen = {}
    until seen.key?("reply") && seen.key?("board")
      event = again.wait_for(deadline: 10) do |e|
        (e.name == "reply" && e.data["id"] == "hold-B1") || (e.name == "board" && plan_on(e.data))
      end
      seen[event.name] = event
    end
    reply, board = seen.values_at("reply", "board")

    expect(reply.data["status"]).to eq("done")
    expect(held(board.data)).to eq([true, false])
  end

  it "keeps run state from the state file and applies a command queued while the engine was down, once" do
    stream = room.sse("/api/events")
    stream.wait_for(deadline: 15) { it.name == "board" && plan_on(it.data) }
    room.post("/api/commands", hold("B1"))
    stream.wait_for(deadline: 10) { it.name == "reply" && it.data["id"] == "hold-B1" }
    room.wait_until(deadline: 10) { live_state["held_questions"].to_a.size == 1 }

    # The engine's own API server is in a process group of its own, so it
    # outlives the engine and keeps the stream open across the restart.
    room.kill(:engine)
    # Only the file is left to remember B1: the engine must restore from it.
    expect(room.redis("DEL", *room.redis("KEYS", "*:run"))).to eq(1)
    queued = room.post("/api/commands", hold("B2"))
    room.start_engine(web_port: ControlRoomProcess.free_port)

    reply = stream.wait_for(deadline: 20) { it.name == "reply" && it.data["id"] == "hold-B2" }
    board = stream.wait_for(deadline: 10) { it.name == "board" && held(it.data) == [true, true] }
    again = room.post("/api/commands", hold("B2"))
    repeat = stream.wait_for(deadline: 10) { it.name == "reply" && it.data["id"] == "hold-B2" }

    expect([queued.code, again.code]).to eq(%w[202 202])
    expect(reply.data["status"]).to eq("done")
    expect(repeat.data["at"]).to eq(reply.data["at"])
    expect(held(board.data)).to eq([true, true])
    room.wait_until(deadline: 10) { live_state["held_questions"].to_a.size == 2 }
  end
end
