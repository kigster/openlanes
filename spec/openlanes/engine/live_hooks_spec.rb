# frozen_string_literal: true

require_relative "../live/live_context"

RSpec.describe "The engine's live hooks" do
  # What the live run (plan 004) asks of the loop: a hook at the top of each
  # tick, words into one agent's control file, a model for an agent's next
  # round, a round handed back, and plans another machine holds stepped around.
  describe OpenLanes::Engine::Dispatcher, :tree do
    include_context "with a live run"

    before { building("001.00", "tax-rule-dsl") }

    let(:job) { dispatcher.running.first }
    let(:seen) { [] }

    it "runs its before-tick hooks first, handing them itself" do
      dispatcher.before_tick { seen << [it, it.running.size] }
      dispatcher.tick
      expect(seen).to eq([[dispatcher, 0]])
    end

    it "knows its runner" do
      expect(dispatcher.runner).to be(runner)
    end

    context "with an agent at work" do
      before { start_agents }

      it "signals it through its control file" do
        aggregate_failures do
          expect(dispatcher.signal(job.key, "HOLD")).to be(true)
          expect(File.read(job.handle.control)).to eq("HOLD\n")
        end
      end

      it "signals and requeues nobody who is not running" do
        expect([dispatcher.signal("001.00/nobody", "HOLD"), dispatcher.requeue("001.00/nobody")]).to eq([false, false])
      end
    end

    context "when a requeued agent stops" do
      let!(:first) do
        start_agents
        dispatcher.running.first
      end

      before do
        dispatcher.requeue(first.key)
        # What INTERRUPT asks of the agent: sign Interrupted and end its turn.
        OpenLanes::Plans::Ledger.append(File.join(path_of("001.00"), first.task.agent.ledger.first),
          "> [2026-09-04 11:29:20 AM PDT] [ agent: #{first.task.agent.name}   status: Interrupted, round 1 ]")
        executor.release_all(1)
        first.thread.join(2)
        start_agents
      end

      it "starts it again, in the same round" do
        expect([executor.calls.count(first.key), job.task.round]).to eq([2, 1])
      end
    end

    context "with an interrupted round in its history" do
      before { dispatcher.send(:remember, "001.00", "luke-backend", :building, "Interrupted", 1) }

      it "hands it back once" do
        expect([dispatcher.resume("001.00", "luke-backend"), dispatcher.resume("001.00", "luke-backend")]).to eq([true, false])
      end
    end

    it "passes a model choice to an executor that can take it" do
      aggregate_failures do
        expect(dispatcher.prefer_model("001.00", "luke-backend", "claude-haiku-5-5")).to be(true)
        expect(executor.preferred).to eq(%w[001.00 luke-backend] => "claude-haiku-5-5")
      end
    end

    context "with an executor that cannot change models" do
      let(:executor) { ->(*, **) {} }

      it "says so" do
        expect(dispatcher.prefer_model("001.00", "luke-backend", "haiku")).to be(false)
      end
    end

    context "when another machine holds the plan" do
      before do
        store.set(keys.claim("001.00"), "them:1")
        dispatcher.tick
      end

      it "steps around it" do
        expect(executor.calls).to eq([])
      end
    end

    context "when another machine takes the plan between the check and the claim" do
      before do
        allow(claims).to receive(:foreign?).and_return(false, true)
        allow(claims).to receive(:claim).and_return(false)
        dispatcher.tick
      end

      it "starts nothing on it" do
        expect(executor.calls).to eq([])
      end
    end
  end

  describe OpenLanes::Engine::Runner, :tree do
    include_context "with a live run"

    before do
      building("001.00", "tax-rule-dsl")
      building("002.00", "ledger")
    end

    let(:one) { tree.subjects.first }
    let(:two) { tree.subjects.last }

    context "when scoped by --plan" do
      let(:scope) { [one.feature.ordinal] }

      it "widens to a plan once" do
        expect([runner.add_plan(two.feature.ordinal), runner.add_plan(two.feature.ordinal), runner.in_scope.size]).to eq([true, false, 2])
      end
    end

    it "has every plan already when it is not scoped" do
      expect(runner.add_plan(two.feature.ordinal)).to be(false)
    end

    context "when another machine holds a plan" do
      before { store.set(keys.claim("002.00"), "them:1") }

      it "claims for itself and knows the foreign one" do
        expect([runner.claim(one), runner.foreign?(two)]).to eq([true, true])
      end
    end

    context "when Redis is gone" do
      before do
        allow(claims).to receive(:claim).and_raise(OpenLanes::Live::Unavailable, "gone")
        allow(claims).to receive(:foreign?).and_raise(OpenLanes::Live::Unavailable, "gone")
        allow(OpenLanes::UI).to receive(:log)
      end

      it "works alone, and says so" do
        aggregate_failures do
          expect([runner.claim(one), runner.foreign?(one)]).to eq([true, false])
          expect(OpenLanes::UI).to have_received(:log).with("claims unchecked: gone").twice
        end
      end
    end

    context "without claims" do
      let(:runner) { described_class.new(tree:, executor:, agents:) }

      it "owns every plan" do
        expect([runner.claim(one), runner.foreign?(one)]).to eq([true, false])
      end
    end
  end
end
