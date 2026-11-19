# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::StartAgain do
  subject(:start) { described_class.new(launcher, invocations) }

  let(:launcher) { instance_double(OpenLanes::Execution::Executor::Launcher, launch: :resumed) }
  let(:invocations) { instance_double(OpenLanes::Execution::Executor::Invocation, argv: %w[claude --resume]) }
  let(:limit) { instance_double(OpenLanes::Execution::Throttle::Limit, to_s: "rate limited", detail: "429") }
  let(:dir) { Dir.mktmpdir("start-again") }
  let(:handle) do
    OpenLanes::Execution::Executor::Handle.new.tap do |handle|
      handle.session = session
      handle.control = File.join(dir, "control")
    end
  end
  let(:session) { "sess-1" }
  let(:failed) { instance_double(OpenLanes::Execution::Transcript, up: spent, down: 0, tools: 0) }
  let(:spent) { 0 }
  let(:sessions) { instance_double(OpenLanes::Execution::Executor::Sessions, current: failed) }
  let(:profile) { OpenLanes::Agents::Profile.new(adapter: OpenLanes::Adapters.for("claude"), model: "opus", effort: "high") }
  let(:attempt) do
    OpenLanes::Execution::Executor::Attempt.new(agent: nil, subject: nil, root: "/r", profile:, trace: nil, handle:, sessions:)
  end

  before { allow(OpenLanes::Execution::Throttle).to receive(:carry_on).and_return("carry on") }

  after { FileUtils.rm_rf(dir) }

  it "makes a start that spent nothing again, as it was" do
    expect(start.call(limit, attempt, -> { :fresh })).to eq(:fresh)
  end

  context "when the failed start had been working" do
    let(:spent) { 500 }

    it "carries its session on" do
      expect(start.call(limit, attempt, -> { :fresh })).to eq(:resumed)
    end
  end

  context "with neither a session nor a way to start over" do
    let(:session) { nil }

    it "gives up and says why" do
      expect([start.call(limit, attempt, nil), handle.throttled])
        .to eq([nil, "rate limited: no session to carry on, and nothing to start again (429)"])
    end
  end
end
