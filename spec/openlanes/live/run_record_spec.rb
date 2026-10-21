# frozen_string_literal: true

require_relative "live_context"

# W6: what a person set from the page survives the engine restarting, from
# Redis normally and from .plans/openlanes-state.json when Redis lost it.
RSpec.describe OpenLanes::Live::RunRecord, :tree do
  subject(:record) { described_class.new(store:, keys:, run_state:) }

  include_context "with a live run"

  let(:state_path) { File.join(plans_root, OpenLanes::Engine::StateFile::FILENAME) }
  let(:state) { OpenLanes::Engine::StateFile.new(path: state_path) }
  let(:dispatcher) { OpenLanes::Engine::Dispatcher.new(runner:, state:, sleeper: ->(_) {}) }

  def saved(seq, models: {}, cars: [])
    { "seq" => seq, "held_questions" => ["001.00/B1"], "held_cars" => cars, "models" => models }
  end

  def in_redis = JSON.parse(store.hget(keys.run, "json"))

  before { building("001.00", "tax-rule-dsl") }

  context "with a person's choices made this run" do
    before do
      record.call(dispatcher)
      run_state.hold_question("001.00/B1")
      run_state.choose_model("001.00/luke-backend", "claude-haiku-5-5")
      record.call(dispatcher)
    end

    it "keeps them in Redis and in the state file, with the same seq" do
      aggregate_failures do
        expect(in_redis).to eq(saved(2, models: { "001.00/luke-backend" => "claude-haiku-5-5" }))
        expect(store.hget(keys.run, "seq")).to eq("2")
        expect(state.live).to eq(in_redis)
      end
    end

    it "writes the state file to disk when the run closes" do
      record.close
      expect(JSON.parse(File.read(state_path))["live"]["seq"]).to eq(2)
    end
  end

  context "when Redis holds the newer copy" do
    before do
      state.live = saved(1)
      store.hset(keys.run, "seq", "3")
      store.hset(keys.run, "json", JSON.generate(saved(3, models: { "001.00/luke-backend" => "claude-haiku-5-5" })))
      record.call(dispatcher)
    end

    it "takes it, hands its models back to the executor, and brings the file up to it" do
      aggregate_failures do
        expect([run_state.seq, run_state.question_held?("001.00/B1")]).to eq([3, true])
        expect(executor.preferred).to eq(%w[001.00 luke-backend] => "claude-haiku-5-5")
        expect(state.live["seq"]).to eq(3)
      end
    end
  end

  context "with a /concurrency set before the restart (plan 020.00)" do
    before { state.live = saved(4).merge("concurrency" => 2) }

    it "hands the limit back to the dispatcher" do
      allow(dispatcher).to receive(:concurrency=)
      record.call(dispatcher)
      expect(dispatcher).to have_received(:concurrency=).with(2)
    end

    it "says so and starts anyway when this run cannot take it" do
      allow(OpenLanes::UI).to receive(:log)
      allow(dispatcher).to receive(:concurrency=).and_raise(OpenLanes::Error, "this run is --isolation shared")
      record.call(dispatcher)
      expect(OpenLanes::UI).to have_received(:log).with(/concurrency 2 from before the restart not kept/)
    end
  end

  context "when Redis came back empty" do
    before do
      state.live = saved(5, cars: ["001.00/luke-backend"])
      record.call(dispatcher)
    end

    it "takes the file's copy and loads it back into Redis" do
      aggregate_failures do
        expect(run_state.car_held?("001.00/luke-backend")).to be(true)
        expect(in_redis["seq"]).to eq(5)
      end
    end
  end

  # Plan 022: after an outage, the same seq rule names the copy that won,
  # and the next flush rewrites the one that is behind.
  context "when reconciling after Redis comes back" do
    before do
      record.call(dispatcher)
      run_state.hold_question("001.00/B1")
      record.call(dispatcher)
    end

    it "names Redis when it kept everything" do
      expect(record.reconcile).to eq(:redis)
    end

    it "names the file when Redis came back empty, and reloads Redis from the engine" do
      store.del(keys.run)
      aggregate_failures do
        expect(record.reconcile).to eq(:file)
        record.flush
        expect(in_redis["seq"]).to eq(run_state.seq)
      end
    end

    it "names the file when Redis rolled back to an older seq" do
      store.hset(keys.run, "seq", "0")
      expect(record.reconcile).to eq(:file)
    end
  end

  it "reconciles to nothing when neither copy exists" do
    expect(record.reconcile).to be_nil
  end

  context "with nothing kept anywhere" do
    before { record.call(dispatcher) }

    it "writes nothing until a person changes something" do
      expect(store.hgetall(keys.run)).to eq({})
    end
  end

  it "reads a garbled Redis copy as none" do
    store.hset(keys.run, "json", "{")
    state.live = saved(2)
    record.call(dispatcher)
    expect(run_state.seq).to eq(2)
  end

  it "carries on, and says so once, when Redis goes away" do
    allow(store).to receive(:hgetall).and_raise(OpenLanes::Live::Unavailable, "gone")
    allow(store).to receive(:multi).and_raise(OpenLanes::Live::Unavailable, "gone")
    allow(OpenLanes::UI).to receive(:log)
    run_state.hold_car("001.00/luke-backend")
    2.times { record.call(dispatcher) }
    expect(OpenLanes::UI).to have_received(:log).with("run state not kept in Redis: gone").once
  end

  describe "through the command stream" do
    let(:commands) { OpenLanes::Live::Commands.new(store:, keys:, node:, run_state:, record:, claims:) }

    it "lands in Redis in the same MULTI as the reply" do
      blocked("002.00", "rebase", "## B1 Rebase\n\nShould I?\n")
      OpenLanes::Live.enqueue(store:, keys:, input: { id: "01JH", kind: "hold_blocked", plan: "002.00", payload: { question: "B1" } })
      commands.call(dispatcher)
      expect(in_redis["held_questions"]).to eq(%w[002.00/B1])
    end
  end
end
