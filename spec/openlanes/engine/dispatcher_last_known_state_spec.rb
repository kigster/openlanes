# frozen_string_literal: true

# The harness's fallback resume record (plan 003, B4): an agent killed before
# it said where it stood gets one from what the harness saw, and an agent
# that did say keeps its own.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:stamp) { "2026-09-04 11:29:20 AM PDT" }
  let(:agents_dir) { Dir.mktmpdir }
  let(:agents) do
    File.write(File.join(agents_dir, "researcher.md"),
      "---\nname: researcher\nhandles: [new]\nadvances_to: researched\nrounds: 1\nledger: [spec.md]\n---\nbody")
    OpenLanes::Agents::Registry.new(dir: agents_dir)
  end
  let(:folder) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).feature.path }
  let(:record) { OpenLanes::Plans::PlanState.for(folder).last_known("researcher") }

  before { plans { |t| t.plan "001.00", :new, "cut-off", files: { "spec.md" => spec_body } } }

  after { FileUtils.rm_rf(agents_dir) }

  # Signs Started, maybe leaves its own record, and is killed at GRACE.
  def killed_agent(&leaves)
    lambda { |agent, subject, round: 1, **|
      OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, "spec.md"),
        "> [#{stamp}] [ agent: #{agent.name}   status: Started, round #{round} ]")
      leaves&.call(subject, round)
      OpenLanes::Execution::Executor::Result.new(ok: false,
        note: "timed out",
        up: 0,
        down: 0,
        subagents: 0,
        delegated: 0,
        seconds: 0.0,
        killed: :timeout)
    }
  end

  def run_with(executor)
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :shared,
      jobs: 1,
      sleeper: ->(_) {},
      extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false)).call
  end

  it "writes a harness record for an agent killed before it left one" do
    run_with(killed_agent)

    aggregate_failures do
      expect(record).to have_attributes(source: "harness", round: 1, status: "Interrupted")
      expect(record.note).to include("timed out", "last ledger line: Started, round 1")
      expect(record.note).not_to include("Interrupted, round 1")
    end
  end

  it "keeps the agent's own record when it left one before it was killed" do
    run_with(killed_agent { |subject, round|
      OpenLanes::Plans::PlanState.for(subject.feature.path).record_last_known("researcher",
        OpenLanes::Plans::LastKnownState.new(source: "agent",
          round:,
          status: "Interrupted",
          next_step: "write the summary",
          done: ["read the sources"]))
    })

    expect(record).to have_attributes(source: "agent", next_step: "write the summary", done: ["read the sources"])
  end

  it "keeps no pid, token or exit field in the record" do
    run_with(killed_agent)

    expect(OpenLanes::Plans::PlanState.for(folder).read.dig("last-known-state", "researcher").keys)
      .to contain_exactly("source", "at", "round", "status", "note")
  end

  it "writes a harness record for an agent whose run raised" do
    run_with(->(*, **) { raise "adapter went away" })

    expect(record).to have_attributes(source: "harness", note: start_with("adapter went away"))
  end

  it "writes a harness record for an agent that exited without being killed" do
    run_with(lambda { |agent, subject, round: 1, **|
      OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, "spec.md"),
        "> [#{stamp}] [ agent: #{agent.name}   status: Almost completed, round #{round} ]")
      OpenLanes::Execution::Executor::Result.new(ok: false, note: "exit 1", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
    })

    expect(record.note).to eq("exit 1; last ledger line: Almost completed, round 1")
  end
end
