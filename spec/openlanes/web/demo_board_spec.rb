# frozen_string_literal: true

# What each command does to the demo's board, as the engine would do it to a
# real one, and how the board moves on its own.
RSpec.describe OpenLanes::Web::DemoBoard do
  subject(:board) { described_class.new }

  let(:me) { board.me }
  let(:plan) { me["plans"].find { it["ordinal"] == ordinal } }
  let(:ordinal) { "001.00" }

  def command(kind, plan: nil, agent: nil, **payload)
    OpenLanes::Live::Command.new(id: "01X", kind:, plan:, agent:, payload: payload.transform_keys(&:to_s))
  end

  def car(key) = me["plans"].flat_map { it["cars"] }.find { it["key"] == key }

  describe "#advance" do
    let(:running) { car("005.00/hansolo-reviewer") }
    let!(:before_up) { running["up"] }

    before { 4.times { board.advance(Time.utc(2026, 10, 13, 9, 0, it)) } }

    it "grows a running car's tokens" do
      expect(running["up"]).to be > before_up
    end

    it "leaves a stuck car's alone" do
      expect(car("001.00/luke-backend")["up"]).to eq(374_000)
    end

    it "turns the running car's message" do
      expect([running["history"].first, described_class::CHATTER.include?(running["message"])]).to eq([running["message"], true])
    end

    it "keeps the run's totals the sum of its plans" do
      expect(me["run"]["up"]).to eq(me["plans"].sum { it["up"] })
    end

    it "moves the other machine's clock too" do
      expect(board.others.first["at"]).to eq("2026-10-13T09:00:03Z")
    end
  end

  describe "answer" do
    before { board.apply(command("answer", plan: ordinal, question: "B1", text: "Yes")) }

    it "removes the question" do
      expect(plan["questions"]).to be_empty
    end

    it "unblocks the plan and its stuck car" do
      expect([plan.dig("status", "key"), car("001.00/luke-backend")["state"]]).to eq(%w[building running])
    end

    context "when the plan is not blocked" do
      let(:ordinal) { "006.00" }

      it "leaves its status as it was" do
        expect(plan.dig("status", "key")).to eq("building")
      end
    end
  end

  describe "hold_blocked and release_hold" do
    it "marks the question held" do
      board.apply(command("hold_blocked", plan: ordinal, question: "B1"))
      expect(plan["questions"].first["held"]).to be(true)
    end

    it "releases it" do
      board.apply(command("hold_blocked", plan: ordinal, question: "1"))
      board.apply(command("release_hold", plan: ordinal, question: "B1"))
      expect(plan["questions"].first["held"]).to be(false)
    end

    it "refuses a question that is not one" do
      expect { board.apply(command("hold_blocked", plan: ordinal, question: "why")) }
        .to raise_error(described_class::Refusal, "why is not a question number like B2")
    end

    it "refuses a question the plan does not have" do
      expect { board.apply(command("hold_blocked", plan: ordinal, question: "B9")) }
        .to raise_error(described_class::Refusal, "001.00 has no open question B9")
    end

    it "refuses a plan not on the board" do
      expect { board.apply(command("hold_blocked", plan: "042.00", question: "B1")) }
        .to raise_error(described_class::Refusal, "there is no plan 042.00")
    end
  end

  describe "resume" do
    it "refuses a plan with nothing interrupted" do
      expect { board.apply(command("resume", plan: ordinal)) }.to raise_error(described_class::Refusal, /no interrupted agent/)
    end

    it "clears the interruption" do
      plan["interrupted"] = { "agent" => "luke-backend", "at" => "2026-10-13T09:00:00Z", "note" => "n" }
      expect([board.apply(command("resume", plan: ordinal)), plan["interrupted"]])
        .to eq(["luke-backend resumes on 001.00 at its next turn", nil])
    end
  end

  describe "discard" do
    before do
      plan["interrupted"] = { "agent" => "luke-backend", "at" => "2026-10-13T09:00:00Z", "note" => "n" }
      board.apply(command("discard", plan: ordinal))
    end

    it "stops every agent on the plan and forgets the interruption" do
      expect([plan["cars"].map { it["state"] }.uniq, plan["interrupted"]]).to eq([["done"], nil])
    end
  end

  describe "message" do
    it "reaches the agent named" do
      board.apply(command("message", plan: ordinal, agent: "rey-frontend", text: "use the grid"))
      expect(car("001.00/rey-frontend")["history"].first).to eq("human: use the grid")
    end

    it "reaches every agent on the plan when none is named" do
      board.apply(command("message", plan: ordinal, text: "lunch"))
      expect(plan["cars"].map { it["history"].first }).to all(eq("human: lunch"))
    end

    it "refuses an agent not on the plan" do
      expect { board.apply(command("message", plan: ordinal, agent: "nobody", text: "hi")) }
        .to raise_error(described_class::Refusal, /none is working 001.00/)
    end
  end

  describe "the car signals" do
    it "holds" do
      board.apply(command("hold", plan: ordinal, agent: "rey-frontend"))
      expect(car("001.00/rey-frontend")["held"]).to be(true)
    end

    it "wraps up" do
      board.apply(command("wrap_up", plan: ordinal, agent: "rey-frontend"))
      expect(car("001.00/rey-frontend").values_at("phase", "held")).to eq(["wrap_up", false])
    end

    it "stops" do
      board.apply(command("stop", plan: ordinal, agent: "rey-frontend"))
      expect(car("001.00/rey-frontend").values_at("phase", "state")).to eq(%w[stopped done])
    end

    it "compacts" do
      board.apply(command("compact", plan: ordinal, agent: "rey-frontend"))
      expect(car("001.00/rey-frontend")["phase"]).to eq("calm")
    end
  end

  describe "stop_all" do
    before { board.apply(command("stop_all")) }

    it "stops every running car and marks the run quitting" do
      expect([me["plans"].flat_map { it["cars"] }.count { it["state"] == "running" }, me["run"]["status"]]).to eq([0, "quitting"])
    end

    it "says one agent in the singular" do
      car("001.00/luke-backend")["state"] = "running"
      expect(board.apply(command("stop_all"))).to eq("stopping 1 agent on dana@studio-mini")
    end
  end

  describe "set_model and switch_model" do
    it "sets the next round's model by label" do
      expect(board.apply(command("set_model", plan: ordinal, agent: "rey-frontend", model: "Haiku 5.5")))
        .to eq("rey-frontend runs on claude-haiku-5-5 from its next round")
    end

    context "when a model is queued for the next round" do
      before { board.apply(command("set_model", plan: ordinal, agent: "rey-frontend", model: "Haiku 5.5")) }

      it "leaves the running model alone and queues the new one as next_model" do
        expect(car("001.00/rey-frontend").slice("model", "next_model"))
          .to eq("model" => "claude-sonnet-5-5", "next_model" => "claude-haiku-5-5")
      end

      it "queues nothing when the model asked for is the one already running" do
        board.apply(command("set_model", plan: ordinal, agent: "rey-frontend", model: "claude-sonnet-5-5"))
        expect(car("001.00/rey-frontend")["next_model"]).to be_nil
      end

      it "clears the queue when the agent is switched now" do
        board.apply(command("switch_model", plan: ordinal, agent: "rey-frontend", model: "claude-opus-5-5"))
        expect(car("001.00/rey-frontend").slice("model", "next_model"))
          .to eq("model" => "claude-opus-5-5", "next_model" => nil)
      end
    end

    it "switches a running agent now" do
      board.apply(command("switch_model", plan: ordinal, agent: "rey-frontend", model: "claude-opus-5-5"))
      expect(car("001.00/rey-frontend")["model"]).to eq("claude-opus-5-5")
    end

    it "refuses to switch an agent that is not running" do
      expect { board.apply(command("switch_model", plan: ordinal, agent: "luke-backend", model: "claude-opus-5-5")) }
        .to raise_error(described_class::Refusal, /not running; use set_model/)
    end

    it "refuses a model that is not offered" do
      expect { board.apply(command("set_model", plan: ordinal, agent: "rey-frontend", model: "gpt-9")) }
        .to raise_error(described_class::Refusal, "claude offers no model gpt-9")
    end
  end

  describe "the lane commands (plan 020.00)" do
    def running_on(ordinal) = me["plans"].find { it["ordinal"] == ordinal }["cars"].count { it["state"] == "running" }

    it "stops every running agent on a plan" do
      expect([board.apply(command("stop_plan", plan: ordinal)), running_on(ordinal)])
        .to eq(["stopped 1 agent on 001.00 and took it off the board", 0])
    end

    it "refuses to restart a plan that still has an agent" do
      expect { board.apply(command("restart_plan", plan: ordinal)) }
        .to raise_error(described_class::Refusal, "001.00 already has an agent: rey-frontend")
    end

    it "restarts a stopped plan's cars and leaves its stuck one waiting" do
      board.apply(command("stop_plan", plan: ordinal))
      expect([board.apply(command("restart_plan", plan: ordinal)), plan["cars"].map { it["state"] }])
        .to eq(["001.00 restarts at the next tick", %w[stuck running]])
    end

    it "refuses a plan not on the board" do
      expect { board.apply(command("stop_plan", plan: "042.00")) }.to raise_error(described_class::Refusal, "there is no plan 042.00")
    end

    it "lowers the limit without stopping anyone" do
      expect([board.apply(command("set_concurrency", limit: 1)), me["run"]["jobs"], running(me).size])
        .to eq(["concurrency 4 → 1; the run waits for 2 agents to finish", 1, 3])
    end

    it "refuses a limit that is not a whole number of at least 1" do
      expect { board.apply(command("set_concurrency", limit: 0)) }
        .to raise_error(described_class::Refusal, "concurrency must be a whole number of at least 1, not 0")
    end

    def running(snapshot) = snapshot["plans"].flat_map { it["cars"] }.select { it["state"] == "running" }
  end

  describe "a kind the demo has no handler for" do
    it "is refused rather than raising on the demo's thread" do
      expect { board.apply(command("pause_discuss", plan: ordinal)) }.to raise_error(described_class::Refusal, "the demo cannot pause_discuss")
    end
  end

  it "carries one approved and one merged plan, finished and with no cars" do
    finished = me["plans"].select { it["finished"] }

    expect(finished.map { [it.dig("finished", "kind"), it.dig("pr", "state"), it["cars"]] })
      .to contain_exactly(["approved", "approved", []], ["merged", "merged", []])
  end

  describe "add_plan" do
    before { board.apply(command("add_plan", plan: "013", ordinal: "013")) }

    it "moves the plan from the backlog onto the board, claimed by this node" do
      expect([me["backlog"].map { it["ordinal"] }, me["plans"].last.values_at("ordinal", "station", "slug", "claimed_by", "finished")])
        .to eq([["012.00"], ["013.00", "new", "plain-nnn-plan-numbers", "3f9a0c7be21d44a8f6031c5d", nil]])
    end

    it "refuses a plan not in the backlog" do
      expect { board.apply(command("add_plan", ordinal: "013")) }.to raise_error(described_class::Refusal, "there is no plan 013.00")
    end

    it "refuses something that is not a plan number" do
      expect { board.apply(command("add_plan", ordinal: "soon")) }.to raise_error(described_class::Refusal, "soon is not a plan number")
    end

    it "puts a plan whose state has no station at the first one" do
      board.apply(command("add_plan", ordinal: "012"))
      expect(me["plans"].last["station"]).to eq("new")
    end
  end

  describe "create_plans" do
    subject(:said) { board.apply(command("create_plans", idea: "# Dark mode toggle\n\nfor the header")) }

    it "adds a new plan after the highest number" do
      said
      expect(me["plans"].last.values_at("ordinal", "title", "status")).to eq(["014.00", "Dark mode toggle", { "key" => "new", "emoji" => "⚪", "label" => "New" }])
    end

    it "says what it created" do
      expect(said).to eq("created 014.00 dark-mode-toggle")
    end
  end
end
