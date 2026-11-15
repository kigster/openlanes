# frozen_string_literal: true

require "json_schemer"

RSpec.describe OpenLanes::Engine::Extensions, :tree do
  subject(:extensions) { described_class.new(stay:, now: -> { now }) }

  let(:stay) { true }
  let(:now) { Time.utc(2026, 10, 16, 9) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:path) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).feature.path }
  let(:plan) { OpenLanes::Plans::PlanState.for(path) }
  let(:handle) { OpenLanes::Execution::Executor::Handle.new }
  let(:left) { 600 }
  let(:clock) { OpenLanes::Execution::Clock.new(seconds: left, control: File.join(path, "control"), on_expire: -> {}, now: -> { 0 }) }

  # The dispatcher's job, as much of it as this class reads.
  let(:job) do
    agent = Struct.new(:name).new("backend-coder")
    task = Struct.new(:agent, :round).new(agent, 1)
    Struct.new(:task, :state, :handle).new(task, :building, handle)
  end

  before do
    plans { |t| t.plan "001.00", :building, "tax-rule-dsl", files: { "spec.md" => spec_body, "plan.md" => "# P" } }
    allow(OpenLanes::UI).to receive(:log)
    handle.clock = clock
  end

  describe "#ask_time, the person's card for a round short of time" do
    def ask(round: 1) = extensions.ask_time(path, agent: "backend-coder", state: :building, round:)

    it "asks once for the round, and keeps asking the same request" do
      2.times { ask }
      expect(plan.extensions).to contain_exactly(include("number" => 1,
        "agent" => "backend-coder",
        "state" => "building",
        "round" => 1,
        "limit" => "time",
        "asked_at" => now.iso8601))
    end

    # Time on the running clock is not the end of it: a person can add more.
    it "asks again once the request was answered with time on the running clock" do
      extensions.answer!(path, ask["number"], "b", by: "pat", live: handle)
      expect(ask).to include("number" => 2).and(satisfy { !it.key?("settled_at") })
    end

    it "does not ask again in a round that was answered with another round" do
      extensions.answer!(path, ask["number"], "a", by: "pat", live: handle)
      expect(ask).to be_nil
    end

    it "says whether it grants on its own, and what time it is" do
      aggregate_failures do
        expect(extensions.automatic?).to be(true)
        expect(described_class.new(stay:, auto: false).automatic?).to be(false)
        expect(extensions.now).to eq(now)
      end
    end
  end

  describe ".questions, with a request the engine is still working out" do
    let(:subject_now) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")) }

    def staged(stage) = plan.ask_extension!(agent: "backend-coder", state: "building", round: 1, limit: "time", stage:)

    it "shows a person no card while the agent or the arbitrator is answering" do
      staged("estimate")
      expect(described_class.questions(subject_now, plan)).to eq([])
    end

    it "shows the card once the request is a person's" do
      plan.amend_extension!(staged("arbitration")["number"], stage: "person")
      expect(described_class.questions(subject_now, plan).map { it[:id] }).to eq(["001.00/X1"])
    end
  end

  describe "#exhausted, an agent with no rounds left" do
    it "waits five minutes for a person on a run with a control room, then gives a round on its own" do
      extensions.exhausted(path, "backend-coder", :building, 1)
      expect(extensions.rounds(path, "backend-coder", :building)).to eq(0)

      later = described_class.new(stay:, now: -> { now + described_class::AUTO_AFTER })
      later.exhausted(path, "backend-coder", :building, 1)
      aggregate_failures do
        expect(plan.extensions.first).to include("limit" => "rounds", "answer" => "a", "by" => "auto", "grant" => "round")
        expect(later.rounds(path, "backend-coder", :building)).to eq(1)
      end
    end

    context "when nobody can answer" do
      let(:stay) { false }

      it "gives the round at once, and only once" do
        extensions.exhausted(path, "backend-coder", :building, 1)
        extensions.exhausted(path, "backend-coder", :building, 2)
        aggregate_failures do
          expect(extensions.rounds(path, "backend-coder", :building)).to eq(1)
          expect(plan.extensions.map { it["round"] }).to eq([1, 2])
          expect(plan.extensions.last).not_to have_key("settled_at")
        end
      end
    end
  end

  describe "#answer!" do
    before { extensions.exhausted(path, "backend-coder", :building, 1) }

    it "gives a round and twenty minutes for it, handed to that round once" do
      extensions.answer!(path, 1, "c", by: "dana")
      aggregate_failures do
        expect(plan.extensions.first).to include("answer" => "c", "by" => "dana", "grant" => "round", "seconds" => 1200)
        expect(extensions.rounds(path, "backend-coder", :building)).to eq(1)
        expect(extensions.take_seconds(path, "backend-coder", :building)).to eq(1200)
        expect(extensions.take_seconds(path, "backend-coder", :building)).to eq(0)
      end
    end

    # A resumed agent may be running while its rounds request is open:
    # every choice on that request is still a round.
    it "gives a round for a time choice on a rounds request, even with a live clock" do
      extensions.answer!(path, 1, "b", by: "dana", live: handle)
      aggregate_failures do
        expect(handle.remaining).to eq(600)
        expect(extensions.rounds(path, "backend-coder", :building)).to eq(1)
      end
    end

    it "still counts a grant made by an earlier engine process on the same visit" do
      extensions.answer!(path, 1, "a", by: "dana")
      later = described_class.new(stay:, now: -> { now + 3600 })
      expect(later.rounds(path, "backend-coder", :building)).to eq(1)
    end

    it "stops counting a grant once the plan moves, even back to the same state" do
      extensions.answer!(path, 1, "a", by: "dana")
      plan.state!(:built)
      plan.state!(:building)
      expect(extensions.rounds(path, "backend-coder", :building)).to eq(0)
    end

    it "counts a grant asked before grants named their visit, for the visit it is answered in" do
      plan.update { |data| data["extensions"].first.delete("moves") }
      extensions.answer!(path, 1, "a", by: "dana")
      expect(extensions.rounds(path, "backend-coder", :building)).to eq(1)
      plan.state!(:built)
      plan.state!(:building)
      expect(extensions.rounds(path, "backend-coder", :building)).to eq(0)
    end

    it "does not count a grant settled before grants named their visit" do
      extensions.answer!(path, 1, "a", by: "dana")
      plan.update { |data| data["extensions"].first.delete("moves") }
      expect(extensions.rounds(path, "backend-coder", :building)).to eq(0)
    end

    it "answers once: a second answer changes nothing" do
      extensions.answer!(path, 1, "a", by: "dana")
      expect(extensions.answer!(path, 1, "c", by: "sam")).to be_nil
      expect(plan.extensions.first).to include("answer" => "a", "by" => "dana")
    end

    it "refuses a letter that is not a choice" do
      expect { extensions.answer!(path, 1, "d", by: "dana") }.to raise_error(ArgumentError, /a\), b\), c\)/)
    end
  end

  describe "#answer! on a time request" do
    before { plan.ask_extension!(agent: "backend-coder", state: :building, round: 1, limit: "time", at: now) }

    it "moves a live clock for a time choice, and gives no round" do
      extensions.answer!(path, 1, "b", by: "dana", live: handle)
      aggregate_failures do
        expect(handle.remaining).to eq(1200)
        expect(extensions.rounds(path, "backend-coder", :building)).to eq(0)
      end
    end

    it "turns the time into a round when the clock already told the agent STOP" do
      clock.extend!(-600)
      clock.tick
      extensions.answer!(path, 1, "c", by: "dana", live: handle)
      aggregate_failures do
        expect(plan.extensions.first).to include("grant" => "round", "seconds" => 1200)
        expect(extensions.rounds(path, "backend-coder", :building)).to eq(1)
      end
    end
  end

  describe "#close!" do
    it "closes the open request of an agent that finished, so the page stops asking" do
      extensions.exhausted(path, "backend-coder", :building, 1)
      extensions.close!(path, "backend-coder", :building)
      expect(plan.extensions.first).to include("closed" => "finished")
    end
  end

  describe ".questions" do
    let(:subject_of) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")) }

    it "shows each open request as an X<n> question with the three choices, the default recommended" do
      extensions.exhausted(path, "backend-coder", :building, 1)
      question = described_class.questions(subject_of, plan).first
      aggregate_failures do
        expect(question).to include(id: "001.00/X1", kind: "extension", heading: "backend-coder is out of rounds", owner: "technical")
        expect(question[:options].map { it[:answer] })
          .to eq(["a) One more round", "b) One more round with 10 extra minutes", "c) One more round with 20 extra minutes"])
        expect(question[:options].map { it[:recommended] }).to eq([true, false, false])
      end
    end

    it "labels a time request's choices with what each grants" do
      plan.ask_extension!(agent: "backend-coder", state: :building, round: 1, limit: "time", at: now)
      expect(described_class.questions(subject_of, plan).first[:options].map { it[:label] })
        .to eq(["One more round, starting again from its resume note", "10 more minutes on this round", "20 more minutes on this round"])
    end

    it "shows nothing settled, and nothing asked on another state" do
      extensions.exhausted(path, "backend-coder", :building, 1)
      extensions.answer!(path, 1, "a", by: "dana")
      plan.ask_extension!(agent: "researcher", state: :new, round: 1, limit: "rounds")
      expect(described_class.questions(subject_of, plan)).to eq([])
    end
  end

  it "validates against the state.json schema" do
    extensions.exhausted(path, "backend-coder", :building, 1)
    extensions.answer!(path, 1, "c", by: "dana")
    extensions.take_seconds(path, "backend-coder", :building)
    schema = JSONSchemer.schema(Pathname.new(OpenLanes::Plans::PlanState::SCHEMA_PATH))
    expect(schema.validate(JSON.parse(File.read(plan.path))).map { it["error"] }).to eq([])
  end
end
