# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Supervision do
  subject(:supervision) { described_class.new(drain:, throttling:, compactor:) }

  let(:drain) { instance_double(OpenLanes::Execution::Executor::Drain, drain: broken) }
  let(:throttling) { instance_double(OpenLanes::Execution::Executor::ThrottleWait) }
  let(:compactor) { instance_double(OpenLanes::Execution::Executor::Compactor) }
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:plan) { Struct.new(:feature).new(Struct.new(:ordinal).new("001.00")) }
  let(:traces) { Dir.mktmpdir("supervision") }
  let(:handle) do
    OpenLanes::Execution::Executor::Handle.new.tap do |handle|
      handle.control = OpenLanes::Execution::Control.register(traces, "001.00-backend-coder")
    end
  end
  let(:clock) { instance_double(OpenLanes::Execution::Clock, stop: nil) }
  let(:sessions) { instance_double(OpenLanes::Execution::Executor::Sessions, current: transcript) }
  let(:attempt) do
    OpenLanes::Execution::Executor::Attempt.new(agent:,
      subject: plan,
      root: "/r",
      profile: nil,
      trace: nil,
      handle:,
      sessions:,
      clock:)
  end
  let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:broken) { instance_double(Process::Status, success?: false, exitstatus: 1) }

  before { allow(throttling).to receive(:ride_out) { |status, *| status } }

  def transcript(**fields)
    instance_double(OpenLanes::Execution::Transcript, { up: 0, down: 0, tools: 0, error: nil, plain: [], failed?: true }.merge(fields))
  end

  after do
    OpenLanes::Execution::Control.reset!
    FileUtils.rm_rf(traces)
  end

  describe "#lost_session" do
    it "counts nothing lost when the session ended well" do
      expect(supervision.lost_session(ok, transcript(failed?: false))).to be_nil
    end

    it "knows the CLI's own words for a session it cannot find" do
      expect(supervision.lost_session(broken, transcript(error: "No conversation found with session ID abc"))).to eq("not found")
    end

    it "takes a failure that spent nothing for a lost session, naming what the CLI said" do
      expect(supervision.lost_session(broken, transcript(plain: ["401 bad key\nmore"])))
        .to eq("failed before spending anything (401 bad key)")
    end

    it "names the exit status when the CLI said nothing" do
      expect(supervision.lost_session(broken, transcript)).to eq("failed before spending anything (exit 1)")
    end

    it "does not take a failure that spent something for a lost session" do
      expect(supervision.lost_session(broken, transcript(up: 10))).to be_nil
    end
  end

  describe "#supervise" do
    it "stops the clock and closes the handle however the agent ends" do
      supervision.supervise(:child, attempt)
      expect(clock).to have_received(:stop)
    end

    it "starts a resumed session that turned out to be gone again fresh" do
      fresh = -> { :fresh_child }
      supervision.supervise(:child, attempt, OpenLanes::Execution::Executor::Restarts.new(resume: "sess-1", relaunch: fresh))
      expect(drain).to have_received(:drain).with(:fresh_child, sessions, handle)
    end

    it "leaves a session that was not resumed alone" do
      supervision.supervise(:child, attempt)
      expect(drain).to have_received(:drain).once
    end
  end
end
