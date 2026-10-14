# frozen_string_literal: true

require_relative "live_context"

RSpec.describe OpenLanes::Live::Commands, :tree do
  subject(:commands) do
    described_class.new(store:, keys:, node:, run_state:, claims:, clock: -> { Time.utc(2026, 10, 13, 9) })
  end

  include_context "with a live run"

  let(:sent) { [] }

  # Queue commands the way the API server does.
  def send_command(kind, plan: nil, agent: nil, id: "C#{sent.size + 1}", **payload)
    sent << id
    OpenLanes::Live.enqueue(store:, keys:, input: { id:, kind:, plan:, agent:, payload: })
  end

  def apply = commands.call(dispatcher)

  def reply_to(id) = JSON.parse(store.hget(keys.done, id))

  def control_of(key) = File.read(dispatcher.job(key).handle.control).strip

  def mailbox(ordinal) = OpenLanes::Plans::Mailbox.new(dir: path_of(ordinal)).messages

  describe "delivery" do
    before do
      building("001.00", "tax-rule-dsl")
      start_agents
      send_command("hold", plan: "001.00", agent: dispatcher.running.first.task.agent.name, id: "01JA")
    end

    it "applies a command once, records its reply in done and on replies, and acknowledges it" do
      aggregate_failures do
        expect(apply.map(&:wire)).to eq([{ id: "01JA", status: "done", reason: nil, at: "2026-10-13T09:00:00Z" }])
        expect(reply_to("01JA")).to include("status" => "done")
        expect(OpenLanes::Live.replies(store:, keys:, after: "0").map(&:last).map { it["id"] }).to eq(%w[01JA])
        expect(store.xreadgroup(keys.commands, OpenLanes::Live::Keys::GROUP, node.name, id: "0")).to eq([])
      end
    end

    context "when the same id arrives again" do
      before do
        apply
        send_command("message", plan: "001.00", agent: "rey-frontend", id: "01JA", text: "second time")
      end

      it "answers it with its first reply, and does not apply it again" do
        aggregate_failures do
          expect(apply.map(&:status)).to eq(%w[done])
          expect(mailbox("001.00")).to be_empty
          expect(OpenLanes::Live.replies(store:, keys:, after: "0").size).to eq(2)
        end
      end
    end

    it "takes up the commands a dead engine read but never acknowledged" do
      store.xgroup_create(keys.commands, OpenLanes::Live::Keys::GROUP)
      store.xreadgroup(keys.commands, OpenLanes::Live::Keys::GROUP, node.name)
      expect(apply.map(&:id)).to eq(%w[01JA])
    end

    it "carries on, and says so, when Redis goes away" do
      allow(store).to receive(:xreadgroup).and_raise(OpenLanes::Live::Unavailable, "gone")
      allow(OpenLanes::UI).to receive(:log)
      expect(apply).to eq([])
      expect(OpenLanes::UI).to have_received(:log).with("commands not read: gone")
    end

    it "says what came from the page, once, naming the plan and agent it addresses" do
      allow(OpenLanes::UI).to receive(:log)
      apply
      apply
      expect(OpenLanes::UI).to have_received(:log)
        .with("from the page: hold", plan: "001.00", agent: dispatcher.running.first.task.agent.name).once
    end

    it "is a block the dispatcher calls at the top of its tick" do
      dispatcher.before_tick(&commands)
      dispatcher.tick
      expect(reply_to("01JA")["status"]).to eq("done")
    end
  end

  describe "a malformed command" do
    it "is refused under its own id when it has one" do
      store.xadd(keys.commands, { json: JSON.generate(id: "01JB", kind: "dance") })
      expect(apply.map { [it.id, it.status, it.reason] }).to match([["01JB", "refused", a_string_including("unknown kind")]])
    end

    context "when it carries no id" do
      let!(:entry) { store.xadd(keys.commands, { json: "{not json" }) }

      it "is refused under its stream id" do
        expect(apply.map { [it.id, it.status] }).to eq([[entry, "refused"]])
      end
    end

    context "when its id is unusable" do
      let!(:entry) { store.xadd(keys.commands, { json: JSON.generate(id: "a b", kind: "stop_all") }) }

      it "is refused under its stream id" do
        expect(apply.map(&:id)).to eq([entry])
      end
    end
  end

  describe "answer" do
    before { blocked("002.00", "rebase", "# Blocked\n\n## B1 Rebase\nanswers: yes, no\n\nShould I rebase?\n") }

    it "appends a signed A<n> to blocked.md" do
      send_command("answer", plan: "002.00", question: "B1", text: "yes")
      apply
      expect(File.read(File.join(path_of("002.00"), "blocked.md")))
        .to end_with("Should I rebase?\n\n## A1\n\nyes\n\nAnswered by dana on 2026-10-13\n<!-- cmd:C1 -->\n")
    end

    # A Redis that fails after the answer is written leaves the command
    # unacknowledged; applied again, it must find its own answer.
    it "writes nothing the second time the same command is applied" do
      send_command("answer", plan: "002.00", question: "B1", text: "yes", id: "01JX")
      allow(store).to receive(:multi).and_raise(OpenLanes::Live::Unavailable, "gone")
      allow(OpenLanes::UI).to receive(:log)
      apply
      allow(store).to receive(:multi).and_call_original
      aggregate_failures do
        expect(apply.map { [it.id, it.status, it.reason] }).to eq([["01JX", "done", nil]])
        expect(File.read(File.join(path_of("002.00"), "blocked.md")).scan("## A1").size).to eq(1)
      end
    end

    it "does not answer twice" do
      File.write(File.join(path_of("002.00"), "blocked.md"), "\n## A1\n\nno\n", mode: "a")
      send_command("answer", plan: "002.00", question: "1", text: "yes")
      expect(apply.map(&:reason)).to eq(["B1 already has an answer waiting"])
    end

    it "refuses a question the file does not ask, a number that is not one, and a plan that is not there" do
      send_command("answer", plan: "002.00", question: "B9", text: "yes")
      send_command("answer", plan: "002.00", question: "Q", text: "yes")
      send_command("answer", plan: "099.00", question: "B1", text: "yes")
      send_command("answer", plan: "x", question: "B1", text: "yes")
      expect(apply.map(&:reason)).to eq(["002.00 has no open question B9", "Q is not a question number like B2",
                                         "there is no plan 099.00", "x is not a plan number"])
    end
  end

  describe "hold_blocked and release_hold" do
    before do
      blocked("002.00", "rebase", "## B1 Rebase\n\nShould I?\n")
      send_command("hold_blocked", plan: "002.00", question: "B1")
      apply
    end

    it "marks the question held in the run state" do
      expect(run_state.question_held?("002.00/B1")).to be(true)
    end

    it "unmarks it when released" do
      send_command("release_hold", plan: "002.00", question: "B1")
      apply
      expect(run_state.question_held?("002.00/B1")).to be(false)
    end
  end

  describe "resume" do
    before { building("001.00", "tax-rule-dsl") }

    it "leaves the person's note for the interrupted agent and hands back its round" do
      OpenLanes::Plans::PlanState.for(path_of("001.00")).stage!(agent: "luke-backend", round: 1, status: "Interrupted")
      allow(dispatcher).to receive(:resume).and_call_original
      send_command("resume", plan: "001.00", note: "the parser is done")
      aggregate_failures do
        expect(apply.map(&:reason)).to eq(["luke-backend resumes on 001.00 at its next turn"])
        expect(mailbox("001.00").map { [it.from, it.to, it.body] }).to eq([["human", "luke-backend", "RESUME: the parser is done"]])
        expect(dispatcher).to have_received(:resume).with(OpenLanes::Plans::Ordinal.parse("001.00"), "luke-backend")
      end
    end

    it "uses a standing note when the person wrote none" do
      OpenLanes::Plans::PlanState.for(path_of("001.00")).stage!(agent: "rey-frontend", round: 1, status: "Interrupted")
      send_command("resume", plan: "001.00")
      apply
      expect(mailbox("001.00").map(&:body)).to eq(["RESUME: carry on from your last resume note"])
    end

    it "refuses a plan nobody was interrupted on" do
      send_command("resume", plan: "001.00")
      expect(apply.map(&:status)).to eq(%w[refused])
    end
  end

  describe "discard in a shared checkout" do
    before { building("001.00", "tax-rule-dsl") }

    it "is refused before any agent is stopped, saying why" do
      send_command("discard", plan: "001.00")
      expect(apply.first.reason).to include("this run has none: under --isolation shared")
    end
  end

  describe "with an agent at work" do
    before do
      building("001.00", "tax-rule-dsl")
      start_agents
    end

    let(:car) { dispatcher.running.first.key }
    let(:agent) { car.split("/").last }
    let(:handle) { dispatcher.job(car).handle }

    %w[hold wrap_up stop].each do |kind|
      it "writes #{kind.upcase} into the agent's control file" do
        send_command(kind, plan: "001.00", agent:)
        apply
        expect(control_of(car)).to eq(kind.upcase)
      end
    end

    context "when a person holds the car" do
      before do
        send_command("hold", plan: "001.00", agent:)
        apply
      end

      it "marks it held" do
        expect(run_state.car_held?(car)).to be(true)
      end

      it "releases it when their message reaches it" do
        send_command("message", plan: "001.00", agent:, text: "use the other parser")
        apply
        aggregate_failures do
          expect(run_state.car_held?(car)).to be(false)
          expect(mailbox("001.00").map { [it.from, it.to, it.body] }).to eq([["human", agent, "use the other parser"]])
        end
      end
    end

    it "sends a message naming no agent to every agent working the plan" do
      send_command("message", plan: "001.00", text: "status?")
      apply
      expect(mailbox("001.00").map(&:to)).to eq([agent])
    end

    it "refuses a word for an agent that is not running" do
      send_command("stop", plan: "001.00", agent: "leah-researcher")
      expect(apply.map(&:reason)).to eq(["001.00/leah-researcher is not running"])
    end

    it "queues a model for the agent's next round" do
      send_command("set_model", plan: "001.00", agent:, model: "haiku")
      aggregate_failures do
        expect(apply.map(&:reason)).to eq(["#{agent} runs on claude-haiku-5-5 from its next round"])
        expect(executor.preferred).to eq(["001.00", agent] => "claude-haiku-5-5")
        expect(run_state.model_for(car)).to eq("claude-haiku-5-5")
      end
    end

    it "refuses a model above the ceiling rather than promising one that will not run" do
      send_command("set_model", plan: "001.00", agent:, model: "fable")
      aggregate_failures do
        expect(apply.map(&:reason)).to eq(["claude offers no model fable"])
        expect(run_state.model_for(car)).to be_nil
      end
    end

    it "appends a message once, however often its command is applied" do
      send_command("message", plan: "001.00", agent:, text: "once", id: "01JM")
      allow(store).to receive(:multi).and_raise(OpenLanes::Live::Unavailable, "gone")
      allow(OpenLanes::UI).to receive(:log)
      apply
      allow(store).to receive(:multi).and_call_original
      apply
      expect(mailbox("001.00").map(&:body)).to eq(%w[once])
    end

    it "refuses a model the adapter does not offer, and an agent that does not exist" do
      send_command("set_model", plan: "001.00", agent:, model: "gpt-9")
      send_command("set_model", plan: "001.00", agent: "nobody", model: "haiku")
      expect(apply.map(&:reason)).to eq(["claude offers no model gpt-9", "no agent called nobody"])
    end

    describe "switch_model" do
      context "when the agent has not named its session" do
        before { send_command("switch_model", plan: "001.00", agent:, model: "claude-opus-5-5") }

        it "falls back to INTERRUPT and a fresh session on the new model, saying why" do
          aggregate_failures do
            expect(apply.first.reason).to eq("#{agent} stops at its next step and restarts on claude-opus-5-5 " \
                                             "from its resume note in a fresh session: it has no session id yet")
            expect(control_of(car)).to eq("INTERRUPT")
          end
        end
      end

      context "when the agent has named its session" do
        before do
          handle.session = "sess-1"
          send_command("switch_model", plan: "001.00", agent:, model: "claude-opus-5-5", id: "01JS")
          apply
        end

        it "compacts it into the new model, and waits for the continuation before replying" do
          aggregate_failures do
            expect(handle.compaction.to_h).to include(model: "claude-opus-5-5", status: nil)
            expect(store.hget(keys.done, "01JS")).to be_nil
            expect(control_of(car)).to eq("INTERRUPT")
          end
        end

        it "replies done once the continuation has started" do
          handle.compaction.done!("#{agent} compacted and carries on on claude-opus-5-5")
          expect(apply.map(&:wire)).to eq([{ id: "01JS", status: "done", reason: "#{agent} compacted and carries on on claude-opus-5-5",
                                             at: "2026-10-13T09:00:00Z" }])
        end
      end

      context "when the agent's CLI cannot resume a session" do
        before do
          handle.session = "sess-1"
          allow(dispatcher).to receive(:adapter_for).and_return(OpenLanes::Adapters.for("codex"))
          send_command("switch_model", plan: "001.00", agent:, model: "claude-opus-5-5")
        end

        it "restarts it on the new model instead" do
          expect(apply.first.reason).to end_with("in a fresh session: codex cannot resume a session")
        end
      end
    end

    describe "compact" do
      context "when the agent has not named its session" do
        before { send_command("compact", plan: "001.00", agent:) }

        it "refuses, falling back to INTERRUPT and a fresh session, and says why" do
          aggregate_failures do
            expect(apply.first).to have_attributes(status: "refused",
              reason: "#{agent} has no session id yet, so it cannot be compacted: it stops at " \
                      "its next step and restarts from its resume note in a fresh session")
            expect(control_of(car)).to eq("INTERRUPT")
          end
        end
      end

      context "when the agent has named its session" do
        before do
          handle.session = "sess-1"
          allow(handle).to receive(:compact!).and_call_original
          send_command("compact", plan: "001.00", agent:, id: "01JC")
          apply
        end

        it "stops the agent for its compaction, on the model it is on, and holds the reply" do
          aggregate_failures do
            expect(handle.compaction.to_h).to include(model: nil, status: nil)
            expect(control_of(car)).to eq("INTERRUPT")
            expect(store.hget(keys.done, "01JC")).to be_nil
          end
        end

        it "replies refused when the compaction could not happen" do
          handle.compaction.refuse!("could not compact #{agent}: /compact exited 1", restart: true)
          expect(apply.map { [it.status, it.reason] }).to eq([["refused", "could not compact #{agent}: /compact exited 1; " \
                                                                          "it restarts from its resume note in a fresh session"]])
        end

        it "answers a repeat of the command with its first reply, and compacts nothing twice" do
          handle.compaction.done!("compacted")
          apply
          send_command("compact", plan: "001.00", agent:, id: "01JC")
          aggregate_failures do
            expect(apply.map { [it.id, it.status, it.reason] }).to eq([%w[01JC done compacted]])
            expect(handle).to have_received(:compact!).once
          end
        end
      end

      it "refuses an agent on a CLI that cannot resume a session" do
        allow(dispatcher).to receive(:adapter_for).and_return(OpenLanes::Adapters.for("pi"))
        send_command("compact", plan: "001.00", agent:)
        expect(apply.first.reason).to eq("pi cannot resume a session, so #{agent} cannot be compacted")
      end

      it "refuses an agent that is not running" do
        send_command("compact", plan: "001.00", agent: "leah-researcher")
        expect(apply.first.reason).to eq("001.00/leah-researcher is not running")
      end
    end

    it "refuses to switch an agent that is not running" do
      send_command("switch_model", plan: "001.00", agent: "leah-researcher", model: "haiku")
      expect(apply.first.reason).to include("use set_model")
    end

    it "stops everything on this node" do
      send_command("stop_all")
      aggregate_failures do
        expect(apply.map(&:reason))
          .to eq(["stopping 1 agent on dana@studio-mini; the engine and the control room shut down once they have gone"])
        expect(OpenLanes::Execution::Control.quit?).to be(true)
      end
    end
  end

  describe "set_model when the executor cannot change models" do
    before { building("001.00", "tax-rule-dsl") }

    let(:executor) { HeldExecutor.new(traces).tap { |e| e.singleton_class.undef_method(:prefer_model) } }

    it "is refused" do
      send_command("set_model", plan: "001.00", agent: "luke-backend", model: "haiku")
      expect(apply.map(&:reason)).to eq(["this run's executor cannot change an agent's model"])
    end
  end

  describe "a message with nobody to read it" do
    before { building("001.00", "tax-rule-dsl") }

    it "is refused" do
      send_command("message", plan: "001.00", text: "hello?")
      expect(apply.map(&:reason)).to eq(["no agent named, and none is working 001.00"])
    end
  end

  describe "add_plan" do
    before do
      building("001.00", "tax-rule-dsl")
      building("003.00", "ledger-export")
      plans { |t| t.plan "004.00", :approved, "done-already", files: { "spec.md" => spec_body } }
    end

    let(:scope) { [OpenLanes::Plans::Ordinal.parse("001.00")] }

    it "claims the plan and widens the run to it" do
      send_command("add_plan", ordinal: "003")
      apply
      aggregate_failures do
        expect(runner.in_scope.map { it.feature.ordinal.to_s }).to eq(%w[001.00 003.00])
        expect(claims.held_by("003.00")).to eq(node.name)
      end
    end

    it "refuses a plan another machine holds, naming the machine" do
      store.set(keys.claim("003.00"), "ffffffffffffffffffffffff:000000000000")
      store.hset(keys.nodes, "ffffffffffffffffffffffff:000000000000", JSON.generate(user: "lee", host: "laptop"))
      send_command("add_plan", ordinal: "003.00")
      expect(apply.map(&:reason)).to eq(["003.00 is being worked on lee@laptop"])
    end

    it "names an unknown holder as another machine" do
      store.set(keys.claim("003.00"), "gone:000000000000")
      send_command("add_plan", ordinal: "003.00")
      expect(apply.map(&:reason)).to eq(["003.00 is being worked on another machine"])
    end

    it "refuses a finished plan, a missing one, and something that is not a number" do
      send_command("add_plan", ordinal: "004.00")
      send_command("add_plan", ordinal: "009.00")
      send_command("add_plan", ordinal: "soon")
      expect(apply.map(&:reason)).to eq(["004.00 is ✅ Approved & Merged, with nothing left to do",
                                         "there is no plan 009.00", "soon is not a plan number"])
    end
  end

  describe "create_plans" do
    before { building("001.00", "tax-rule-dsl") }

    let(:scope) { [OpenLanes::Plans::Ordinal.parse("001.00")] }

    let(:created) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("002.00")) }

    it "creates a ⚪️ plan whose spec opens with the idea, claims it, and adds it to the run" do
      send_command("create_plans", idea: "Export the ledger as CSV for the accountant")
      aggregate_failures do
        expect(apply.map(&:reason)).to eq(["created 002.00 export-the-ledger-as-csv-for-the-accountant"])
        expect(created.status.key).to eq(:new)
        expect(created.read("spec.md")).to include("Export the ledger as CSV for the accountant")
        expect(runner.in_scope.map { it.feature.ordinal.to_s }).to eq(%w[001.00 002.00])
        expect(claims.held).to include("002.00")
      end
    end

    it "names the plan after an idea's heading, once" do
      send_command("create_plans", idea: "# Minesweeper\n\nMinesweeper is played on a grid of covered squares.")
      expect(apply.map(&:reason)).to eq(["created 002.00 minesweeper"])
    end

    it "creates one plan however often its command is applied" do
      send_command("create_plans", idea: "Export the ledger as CSV", id: "01JC")
      allow(store).to receive(:multi).and_raise(OpenLanes::Live::Unavailable, "gone")
      allow(OpenLanes::UI).to receive(:log)
      apply
      allow(store).to receive(:multi).and_call_original
      aggregate_failures do
        expect(apply.map(&:reason)).to eq(["created 002.00 export-the-ledger-as-csv"])
        expect(tree.reload.ordinals.map(&:to_s)).to eq(%w[001.00 002.00])
      end
    end

    context "with the idea dialog's form" do
      before do
        send_command("create_plans",
          idea:        "A tic-tac-toe game",
          frontmatter: { lane: "quick", research: false, frontend: "false", depth: "fast" })
        apply
      end

      let(:spec) { OpenLanes::Plans::Spec.for(created) }

      it "writes the lane, front end and depth into spec.md, where routing reads them" do
        aggregate_failures do
          expect([spec.lane, spec.frontend, spec.depth]).to eq([:quick, false, :fast])
          expect(spec.problems).to be_empty
          expect(created.read("spec.md")).to include("A tic-tac-toe game")
        end
      end
    end

    context "when the form leaves everything to the plan" do
      before do
        send_command("create_plans",
          idea:        "A tic-tac-toe game",
          frontmatter: { lane: "full", research: true, frontend: "auto", depth: "auto" })
        apply
      end

      it "writes only the lane, and nothing for auto or research" do
        expect(created.read("spec.md")).to start_with("---\nlane: full\n---\n\n# ")
      end
    end

    it "writes no frontmatter when the command carries no form" do
      send_command("create_plans", idea: "A tic-tac-toe game")
      apply
      expect(created.read("spec.md")).to start_with("# ")
    end

    it "refuses an idea that makes no folder name" do
      send_command("create_plans", idea: "!!!")
      expect(apply.first.reason).to start_with("could not create the plan")
    end
  end

  describe "a handler that breaks" do
    before { building("001.00", "tax-rule-dsl") }

    it "is refused with what broke, and logged" do
      allow(OpenLanes::Plans::Mailbox).to receive(:new).and_raise(IOError, "disk full")
      allow(OpenLanes::UI).to receive(:log)
      start_agents
      send_command("message", plan: "001.00", text: "hi")
      aggregate_failures do
        expect(apply.map(&:reason)).to eq(["message failed: disk full"])
        expect(OpenLanes::UI).to have_received(:log).with("message failed: IOError: disk full", plan: "001.00")
      end
    end
  end

  describe "the done hash" do
    it "forgets replies older than a day, and keeps the rest" do
      store.hset(keys.done, "old", JSON.generate(id: "old", status: "done", reason: nil, at: "2026-10-11T09:00:00Z"))
      store.hset(keys.done, "new", JSON.generate(id: "new", status: "done", reason: nil, at: "2026-10-13T08:00:00Z"))
      apply
      expect(store.hgetall(keys.done).keys).to eq(%w[new])
    end

    it "drops what it cannot read, one entry at a time, and keeps the rest" do
      store.hset(keys.done, "bad", "{")
      store.hset(keys.done, "numeric", JSON.generate(id: "numeric", at: 12))
      store.hset(keys.done, "new", JSON.generate(id: "new", status: "done", reason: nil, at: "2026-10-13T08:00:00Z"))
      apply
      expect(store.hgetall(keys.done).keys).to eq(%w[new])
    end
  end
end
