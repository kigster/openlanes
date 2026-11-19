# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Compactor do
  subject(:compactor) { described_class.new(launcher:, invocations:, drain:) }

  let(:launcher) { instance_double(OpenLanes::Execution::Executor::Launcher, launch: :child) }
  let(:invocations) { instance_double(OpenLanes::Execution::Executor::Invocation, argv: %w[claude]) }
  let(:drain) { instance_double(OpenLanes::Execution::Executor::Drain, drain: :ended) }
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:handle) { OpenLanes::Execution::Executor::Handle.new.tap { it.session = session } }
  let(:session) { "sess-1" }
  let(:adapter) { OpenLanes::Adapters.for(adapter_name) }
  let(:adapter_name) { "claude" }
  let(:profile) { OpenLanes::Agents::Profile.new(adapter:, model: "opus", effort: "high") }
  let(:attempt) do
    OpenLanes::Execution::Executor::Attempt.new(agent:, subject: nil, root: "/r", profile:, trace: nil, handle:, sessions: nil)
  end
  let(:compaction) { OpenLanes::Execution::Executor::Compaction.new }

  context "when the agent was stopped first" do
    before { handle.kill!(grace: 0, reason: :key) }

    it "refuses" do
      expect([compactor.carry_on(compaction, attempt), compaction.reason]).to eq([nil, "backend-coder was stopped first (key)"])
    end

    it "starts nothing" do
      compactor.carry_on(compaction, attempt)
      expect(launcher).not_to have_received(:launch)
    end
  end

  context "without a session id" do
    let(:session) { nil }

    it "refuses and gives the agent its round back" do
      compactor.carry_on(compaction, attempt)
      expect([compaction.reason, compaction.restart]).to eq(["could not compact backend-coder: no session id to resume; " \
                                                             "it restarts from its resume note in a fresh session", true])
    end
  end

  it "answers the person when the continuation cannot even start" do
    expect { compactor.settling(compaction, agent) { raise IOError, "pipe" } }.to raise_error(IOError)
    expect(compaction.reason).to eq("could not compact backend-coder: pipe")
  end

  it "leaves an answer already given alone" do
    compaction.done!("compacted")
    expect { compactor.settling(compaction, agent) { raise IOError, "pipe" } }.to raise_error(IOError)
    expect(compaction.reason).to eq("compacted")
  end
end
