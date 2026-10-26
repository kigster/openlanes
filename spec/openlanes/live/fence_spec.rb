# frozen_string_literal: true

require_relative "live_context"

# W26: no two machines work one plan. A node that lost a claim stops its
# agents on that plan, and one that never held it does not rename it.
RSpec.describe "Plans another machine holds", :tree do
  include_context "with a live run"

  let(:other) { "ffffffffffffffffffffffff:000000000000" }

  before do
    stub_const("OpenLanes::Engine::Dispatcher::KILL_GRACE", 0)
    allow(OpenLanes::UI).to receive(:log)
  end

  context "when this node's claim is taken while its agents work" do
    before do
      building("001.00", "tax-rule-dsl")
      start_agents
      dispatcher.fence(%w[001.00])
      executor.release_all
      dispatcher.running.each { it.thread.join(2) }
      dispatcher.tick
    end

    it "stops them, signs nothing for them, and drops the plan from the run" do
      aggregate_failures do
        expect(dispatcher.attempts.map(&:note).uniq).to eq(["claim lost to another machine"])
        expect(runner.in_scope).to be_empty
        expect(dispatcher.running).to be_empty
      end
    end

    it "takes the plan back when a person adds it again" do
      runner.add_plan(OpenLanes::Plans::Ordinal.parse("001.00"))
      expect(runner.in_scope.map { it.feature.ordinal.to_s }).to eq(%w[001.00])
    end
  end

  context "when a folder's name lags its contents" do
    # ⚪️ with a plan in it: resync would rename it, and must not.
    before do
      plans { |t| t.plan "003.00", :new, "theirs", files: { "spec.md" => spec_body, "plan.md" => "" } }
      store.set(keys.claim("003.00"), other)
      dispatcher.tick
    end

    it "leaves the name to the machine that holds the plan" do
      expect(tree.reload.find("003.00").status.key).to eq(:new)
    end
  end

  context "when a stage that machine started looks stranded" do
    let(:state) { OpenLanes::Engine::StateFile.new(path: File.join(plans_root, "openlanes-state.json"), pid: 999_999_999) }
    let(:dispatcher) { OpenLanes::Engine::Dispatcher.new(runner:, state:, sleeper: ->(_) {}) }

    before do
      building("003.00", "theirs")
      OpenLanes::Plans::PlanState.for(path_of("003.00")).stage!(agent: "backend-coder",
        round: 1,
        status: "Started",
        run: { pid: 999_999_999, host: Socket.gethostname })
      store.set(keys.claim("003.00"), other)
      allow(executor).to receive(:call)
      dispatcher.send(:resume_stranded)
    end

    it "is not marked interrupted by this one" do
      expect(OpenLanes::Plans::PlanState.for(path_of("003.00")).stages.map { it["status"] }).to eq(%w[Started])
    end
  end
end
