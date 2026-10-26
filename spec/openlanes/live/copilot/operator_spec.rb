# frozen_string_literal: true

# copilot answering, with `claude` replaced at the spawn seam by a fake
# that plays back a stream-json transcript. Nothing here starts a process.
RSpec.describe OpenLanes::Live::Copilot::Operator do
  subject(:operator) { described_class.new(root:, plans_dir:, stores:, keys:, spawn:, trace_dir:, agent:) }

  let(:agent) { OpenLanes::Agents.find("copilot") }
  let(:root) { Dir.mktmpdir("copilot") }
  let(:plans_dir) { File.join(root, ".plans") }
  let(:trace_dir) { File.join(root, "traces") }
  let(:store) { OpenLanes::Live.memory_store }
  let(:stores) { OpenLanes::Web::Stores.shared(store) }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:copilot) { OpenLanes::Live.copilot(store:, keys:, responder: operator) }
  let(:turn_class) { OpenLanes::Live::Copilot::Turn }

  # What each spawn plays back, in order: one entry per `claude -p`.
  let(:runs) { [run(session: "sess-1", sent: 1000, said: 50, result: "002 is waiting on you.")] }
  let(:spawned) { [] }
  let(:spawn) do
    lambda do |argv, chdir:, env:|
      spawned << { argv:, chdir:, env: }
      play = runs.fetch(spawned.size - 1)
      child = instance_double(OpenLanes::Execution::Child,
        pid:       4242,
        terminate: nil,
        wait:      instance_double(Process::Status, success?: play[:ok], exitstatus: play[:ok] ? 0 : 1))
      allow(child).to receive(:each_chunk) { |&block| play[:lines].each { block.call("#{it}\n") } }
      child
    end
  end

  let(:board) do
    { seq: 3, at: "2026-10-13T20:00:00Z", node: { id: "aaaa", user: "pat", host: "box", me: true },
      run: { status: "running", up: 5000, down: 300, cost: 0.42, agents_working: 1 },
      plans: [{ ordinal: "002.00", title: "Cart retention", status: { emoji: "🔨", label: "Building" }, starts: "research",
                elapsed: 600, cost: 0.4, pr: nil, interrupted: nil,
                cars: [{ key: "002.00/backend-coder", agent: "backend-coder", state: "running", phase: "calm", round: 1, rounds: 2,
                         model: "claude-opus-5-5", up: 5000, down: 300, elapsed: 600, remaining: 300, held: false,
                         message: "Running rspec" }],
                questions: [{ id: "002.00/B1", owner: "product", agent: "backend-coder", held: false,
                              heading: "B1 Retention", body: "How long are carts kept?" }] }],
      backlog: [], log: [{ at: "2026-10-13T19:59:00Z", source: "engine", level: "info", text: "round 2 started" }] }
  end

  # One `claude -p` as stream-json: init, the settled usage, the result.
  def run(session:, sent:, said:, result:, exited: true, error: false)
    lines = []
    lines << JSON.generate(type: "system", subtype: "init", session_id: session) if session
    lines << JSON.generate(type: "stream_event", event: { type: "message_delta", usage: { input_tokens: sent, output_tokens: said } }) if sent.positive?
    lines << JSON.generate(type: "result", result:, is_error: error, usage: { input_tokens: sent, output_tokens: said })
    { ok: exited, lines: }
  end

  # What the API server does: store the message, then answer it.
  def say(text, id: "01JMSG") = copilot.answer(copilot.say({ "id" => id, "text" => text }))

  def stored = store.xrange(keys.copilot).map { JSON.parse(it.fields["json"]) }

  after { FileUtils.rm_rf(root) }

  describe "the boundary" do
    let(:argv) { operator.argv("hello", nil) }

    def flag(name) = argv[argv.index(name) + 1]

    it "fixes the tool set, so no settings file can add one" do
      expect([flag("--tools"), argv.include?("--restricted"), flag("--permission-mode")]).to eq(["Read,Grep,Glob,Bash", true, "dontAsk"])
    end

    it "lets Bash run only the read-only openlanes queries" do
      bash = flag("--allowedTools").split(",").grep(/\ABash/)
      expect(bash).to all(start_with("Bash(openlanes ")).and include("Bash(openlanes plans:*)", "Bash(openlanes state show:*)")
    end

    it "denies writing, sub-agents, the network and what the plan agents may never run" do
      expect(flag("--disallowedTools").split(","))
        .to include("Edit", "Write", "NotebookEdit", "Task", "WebFetch", "WebSearch", "Bash(git push:*)", "Bash(gh pr merge:*)")
    end

    it "reads the agents' transcripts from the trace directory as well as the checkout" do
      expect(argv.each_cons(2).select { it.first == "--add-dir" }.map(&:last)).to eq([root, trace_dir])
    end

    it "runs on its definition's cheap model, with its definition as the standing instructions" do
      expect([flag("--model"), flag("--append-system-prompt")]).to eq(["haiku", agent.prompt])
    end

    it "does not ask for the board's one-line status tool" do
      expect(argv).not_to include("--brief")
    end

    it "resumes the conversation it is given" do
      expect(operator.argv("hello", "sess-1").each_cons(2).to_a).to include(["--resume", "sess-1"])
    end
  end

  describe "answering" do
    before { store.set(keys.snapshot, JSON.generate(board)) }

    it "stores the person's turn and then the copilot's" do
      say("Why has 002 not moved?")
      expect(stored.map { it.values_at("id", "from", "kind", "text") })
        .to eq([%w[01JMSG you text Why\ has\ 002\ not\ moved?], %w[01JMSG.1 copilot text 002\ is\ waiting\ on\ you.]])
    end

    it "starts a fresh conversation the first time, in the checkout" do
      say("hi")
      expect([spawned.first[:argv].include?("--resume"), spawned.first[:chdir]]).to eq([false, root])
    end

    it "keeps the session id beside the conversation" do
      say("hi")
      expect(store.hgetall(keys.copilot_session)).to include("session" => "sess-1", "up" => "1000", "down" => "50")
    end

    it "tells the agent the board and the person's words" do
      say("Why has 002 not moved?")
      expect(spawned.first[:argv][2]).to include("002.00 Cart retention: 🔨 Building",
        "car 002.00/backend-coder: running",
        "question 002.00/B1",
        "round 2 started",
        "## The person says\n\nWhy has 002 not moved?")
    end

    it "gives every answer the model and the running total, which the header shows" do
      say("hi")
      expect([stored.last["usage"], copilot.history[:usage]])
        .to eq([{ "model" => "claude-haiku-5-5", "up" => 1000, "down" => 50 }] * 2)
    end

    context "with a second message" do
      let(:runs) do
        [run(session: "sess-1", sent: 1000, said: 50, result: "one"), run(session: "sess-1", sent: 400, said: 20, result: "two")]
      end

      before do
        say("first", id: "01JA")
        say("second", id: "01JB")
      end

      it "resumes the same session" do
        expect(spawned.last[:argv].each_cons(2).to_a).to include(["--resume", "sess-1"])
      end

      it "adds what the second spent to the first" do
        expect(stored.last["usage"]).to eq("model" => "claude-haiku-5-5", "up" => 1400, "down" => 70)
      end
    end

    context "when a server restarted since the last message" do
      before { store.hset(keys.copilot_session, "session", "sess-0") }

      it "carries on the session Redis kept" do
        say("still there?")
        expect(spawned.first[:argv].each_cons(2).to_a).to include(["--resume", "sess-0"])
      end
    end

    # What `claude -p --resume` prints for a session it does not have: the
    # reason on stderr, and a result event with no result.
    def missing(id)
      { ok: false, lines: ["No conversation found with session ID: #{id}",
                           JSON.generate(type: "result",
                             subtype: "error_during_execution",
                             is_error: true,
                             session_id: id,
                             usage: { input_tokens: 0, output_tokens: 0 },
                             errors: ["No conversation found with session ID: #{id}"])] }
    end

    context "when claude no longer has the session" do
      let(:runs) { [missing("sess-0"), run(session: "sess-2", sent: 900, said: 40, result: "Starting afresh.")] }

      before do
        store.hset(keys.copilot_session, "session", "sess-0")
        say("hello")
      end

      it "starts a new conversation and keeps its id" do
        expect([spawned.map { it[:argv].include?("--resume") }, store.hget(keys.copilot_session, "session")])
          .to eq([[true, false], "sess-2"])
      end

      it "answers from the new one" do
        expect(stored.last["text"]).to eq("Starting afresh.")
      end
    end

    context "when the fresh conversation fails as well" do
      let(:runs) { [missing("sess-0"), run(session: nil, sent: 0, said: 0, result: "Not logged in", exited: false, error: true)] }

      before do
        store.hset(keys.copilot_session, "session", "sess-0")
        say("hello")
      end

      it "forgets the session claude does not have" do
        expect([spawned.size, store.hget(keys.copilot_session, "session")]).to eq([2, nil])
      end
    end

    context "when a resumed run fails before spending anything, for another reason" do
      let(:runs) { [run(session: nil, sent: 0, said: 0, result: "Invalid API key", exited: false, error: true)] }

      before do
        store.hset(keys.copilot_session, "session", "sess-0")
        say("hello")
      end

      it "reports it rather than starting again" do
        expect([spawned.size, store.hget(keys.copilot_session, "session"), stored.last["text"]])
          .to match([1, "sess-0", /claude reported: Invalid API key/])
      end
    end

    context "when the run fails" do
      let(:runs) { [run(session: "sess-1", sent: 300, said: 0, result: "API Error: overloaded", exited: false, error: true)] }

      before { say("hi") }

      it "says why in the conversation, with what it spent" do
        expect(stored.last).to include("kind" => "text",
          "text" => start_with("copilot could not answer: claude reported: API Error"),
          "usage" => { "model" => "claude-haiku-5-5", "up" => 300, "down" => 0 })
      end

      it "does not retry a session that did start" do
        expect(spawned.size).to eq(1)
      end
    end

    context "when the answer proposes a stop" do
      let(:stop) do
        { card: "confirm", text: "backend-coder is stuck.", command: { kind: "stop", plan: "002", agent: "backend-coder" },
          confirm: "Stop backend-coder", done: "Asked to stop." }
      end
      let(:runs) { [run(session: "s", sent: 10, said: 5, result: "Look:\n```copilot\n#{JSON.generate(stop)}\n```")] }

      it "stores a confirm card the page can draw, and sends nothing" do
        say("stop backend-coder")
        expect([stored.map { it["kind"] }, store.xlen(keys.commands)]).to eq([%w[text text confirm], 0])
      end
    end

    context "when the answer proposes a message to an agent" do
      let(:message) { { card: "confirm", command: { kind: "message", plan: "002", payload: { text: "push now" } }, confirm: "Send", done: "ok" } }
      let(:runs) { [run(session: "s", sent: 10, said: 5, result: "```copilot\n#{JSON.generate(message)}\n```")] }

      it "turns it into text and sends nothing" do
        say("tell backend-coder to push")
        expect([stored.last["kind"], stored.last["text"], store.xlen(keys.commands)]).to match(["text", /not a command copilot may offer/, 0])
      end
    end

    context "with no engine publishing a board" do
      before { store.del(keys.snapshot) }

      it "says so in the brief, rather than inventing one" do
        say("hi")
        expect(spawned.first[:argv][2]).to include("No engine is publishing a board")
      end
    end
  end

  context "when the server is stopping" do
    it "cuts the answer under way short and answers the next with why" do
      operator.stop
      say("hi")
      expect([spawned, stored.last["text"]]).to eq([[], "copilot could not answer: the server is stopping"])
    end
  end

  context "when the server stops while claude is starting" do
    let(:child) do
      instance_double(OpenLanes::Execution::Child,
        pid:        1,
        terminate:  nil,
        each_chunk: nil,
        wait:       instance_double(Process::Status, success?: false, exitstatus: nil))
    end
    let(:spawn) do
      lambda do |argv, **|
        spawned << argv
        operator.stop
        child
      end
    end

    it "ends the child it was too late to see" do
      say("hi")
      expect(child).to have_received(:terminate).with(grace: 1, drain: 1)
    end
  end

  context "when claude cannot be started" do
    let(:spawn) { ->(*, **) { raise Errno::ENOENT, "claude" } }
    let(:transcripts) { [] }

    before do
      allow(OpenLanes::Execution::Transcript).to(receive(:new).and_wrap_original { |m, **kw| m.call(**kw).tap { transcripts << it } })
    end

    it "closes the trace it opened" do
      say("hi")
      expect(transcripts.map { it.instance_variable_get(:@trace) }).to eq([nil])
    end
  end

  context "when two messages arrive at once" do
    let(:runs) { Array.new(2) { run(session: "s", sent: 10, said: 5, result: "ok") } }
    let(:spawn) do
      lambda do |_argv, **|
        spawned << :start
        sleep 0.05
        spawned << :end
        play = run(session: "s", sent: 10, said: 5, result: "ok")
        child = instance_double(OpenLanes::Execution::Child, pid: 1, terminate: nil, wait: instance_double(Process::Status, success?: true, exitstatus: 0))
        allow(child).to receive(:each_chunk) { |&block| play[:lines].each { block.call("#{it}\n") } }
        child
      end
    end

    it "answers them one after the other, never two sessions at once" do
      turns = %w[01JA 01JB].map { copilot.say({ "id" => it, "text" => "hi" }) }
      turns.map { |turn| Thread.new { operator.call(turn) } }.each(&:join)
      expect(spawned).to eq(%i[start end start end])
    end
  end

  context "when an answer takes too long" do
    let(:agent) { OpenLanes::Agents.find("copilot").with(timeout: 0.1) }
    let(:spawn) do
      lambda do |argv, chdir:, env:|
        spawned << { argv:, chdir:, env: }
        ended = false
        child = instance_double(OpenLanes::Execution::Child, pid: 1, wait: instance_double(Process::Status, success?: false, exitstatus: nil))
        allow(child).to receive(:terminate) { ended = true }
        allow(child).to receive(:each_chunk) { sleep 0.01 until ended }
        child
      end
    end

    it "is ended, and the person told why" do
      say("hi")
      expect(stored.last["text"]).to include("took longer than 0.1 seconds")
    end
  end

  it "refuses to start without its definition" do
    expect { described_class.new(root: "/", plans_dir: "/", stores:, keys:, agent: nil) }
      .to raise_error(OpenLanes::Error, /no agent definition named copilot/)
  end
end
