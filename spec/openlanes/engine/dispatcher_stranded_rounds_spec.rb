# frozen_string_literal: true

require "socket"
require_relative "round_engine_context"

# Issue 255, findings 2 and 3: a round `state.json` still calls Started when
# an engine starts was lost by the harness, not spent by the agent. The agent
# here has one round, as every shipped agent does, so a round wrongly counted
# leaves it with none.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a restartable engine"

  let(:agent_front) { "handles: [new]\nadvances_to: researched\nrounds: 1\nadapter: claude\nledger: [spec.md]" }
  let(:run) { {} }
  # What an engine writes as a round starts, a minute ago, and nothing since.
  let(:lost) { { status: "Started", from: "new", state: "new", started_at: (clock.now - 60).iso8601 } }
  let(:mail) { OpenLanes::Plans::Mailbox.new(dir: folder).messages.map(&:body) }

  before do
    plans { |t| t.plan "001.00", :new, "carry-on", files: { "spec.md" => spec_body } }
    plan_state.stage!(agent: "researcher", round: 1, reset: true, **lost, **run)
  end

  # A pid that is certainly dead: a child that has been waited for.
  def dead_pid = Process.spawn("true").tap { Process.wait(it) }

  shared_examples "a round the harness lost" do
    it "starts the agent again on the same round" do
      engine

      expect(told).to eq([1])
    end

    it "writes the lost round as handed back, which spends nothing" do
      engine

      expect(stages.first.values_at("status", "note", "handed_back")).to eq(["Interrupted", "harness died", true])
    end

    it "leaves the agent a resume note and tells it to carry on from it" do
      engine

      aggregate_failures do
        expect(plan_state.signatures.first.values_at("status", "note")).to eq(["Interrupted", "harness died"])
        expect(mail.first).to start_with("RESUME: the harness died during your round 1")
      end
    end

    it "raises no request for rounds before the agent has had its own" do
      asked = nil
      engine(executor: lambda { |*args, **options|
        asked = plan_state.extensions.size
        executor.call(*args, **options)
      })

      expect(asked).to eq(0)
    end
  end

  context "when the dead engine was an older release's, which left its pid on the stage" do
    let(:run) { { run: { "pid" => dead_pid, "host" => Socket.gethostname } } }

    it_behaves_like "a round the harness lost"
  end

  context "when no restart record knows the stage at all" do
    it_behaves_like "a round the harness lost"
  end

  context "when another live run holds the plan's lock" do
    # The suite's parent process: alive, and not this one.
    before { OpenLanes::Plans::Lock.write(folder, pid: Process.ppid) }

    after { OpenLanes::Plans::Lock.remove(folder) }

    it "leaves the Started round to that run" do
      engine

      expect([told, stages.map { it["status"] }]).to eq([[], ["Started"]])
    end
  end
end
