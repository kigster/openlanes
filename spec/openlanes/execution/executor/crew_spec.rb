# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Crew do
  subject(:crew) { described_class.build(options, preferences, invocations) }

  let(:spawn) { ->(_argv, **) {} }
  let(:options) { OpenLanes::Execution::Executor::Options.new(root: ".", spawn:, trace_dir: "/traces", max_tokens: 9) }
  let(:preferences) { instance_double(OpenLanes::Execution::Executor::Preferences) }
  let(:invocations) { instance_double(OpenLanes::Execution::Executor::Invocation) }

  it "wires one of each collaborator" do
    expect([crew.launcher, crew.supervision, crew.verdict]).to all(be_a(Object))
    expect(crew.launcher).to be_a(OpenLanes::Execution::Executor::Launcher)
    expect(crew.supervision).to be_a(OpenLanes::Execution::Executor::Supervision)
    expect(crew.verdict).to be_a(OpenLanes::Execution::Executor::Verdict)
  end

  it "keeps what it was handed" do
    expect([crew.invocations, crew.preferences, crew.trace_dir]).to eq([invocations, preferences, "/traces"])
  end

  it "starts processes through the spawn it was given" do
    allow(OpenLanes::Execution::Executor::Launcher).to receive(:new).and_call_original
    crew
    expect(OpenLanes::Execution::Executor::Launcher).to have_received(:new).with(spawn:)
  end

  context "without a spawn" do
    let(:spawn) { nil }
    let(:starter) { instance_double(OpenLanes::Execution::AgentProcess::Starter) }

    before { allow(OpenLanes::Execution::AgentProcess).to receive(:spawner).and_return(starter) }

    it "starts them through the agent supervisor, in the trace directory and the checkout" do
      allow(OpenLanes::Execution::Executor::Launcher).to receive(:new).and_call_original
      crew
      expect(OpenLanes::Execution::AgentProcess).to have_received(:spawner).with(dir: "/traces", root: File.expand_path("."))
      expect(OpenLanes::Execution::Executor::Launcher).to have_received(:new).with(spawn: starter)
    end
  end
end
