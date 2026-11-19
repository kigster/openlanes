# frozen_string_literal: true

# One invocation from its first start to its verdict, over a crew of doubles:
# what FirstStart arranges around the launch, the supervision and the judgement,
# and in which order. The crew's own behaviour has its own specs.
RSpec.describe OpenLanes::Execution::Executor::FirstStart do
  subject(:first_start) { described_class.new(crew) }

  let(:executor) { OpenLanes::Execution::Executor }
  let(:traces) { Dir.mktmpdir("first-start") }
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:subject_plan) { Struct.new(:feature).new(Struct.new(:ordinal, :path).new("001.00", File.join(traces, "plan"))) }
  let(:adapter) { OpenLanes::Adapters.for("claude") }
  let(:profile) { OpenLanes::Agents::Profile.new(adapter:, model: nil, effort: nil) }
  let(:handle) { executor::Handle.new }
  let(:sessions) { executor::Sessions.new }
  let(:attempt) do
    executor::Attempt.new(agent:, subject: subject_plan, root: traces, profile:, trace: File.join(traces, "t.ndjson"), handle:, sessions:)
  end
  let(:request) { executor::Request.new(root: traces, round: 2) }
  let(:started) { OpenLanes::UI.monotonic }

  let(:child) { instance_double(OpenLanes::Execution::AgentProcess) }
  let(:status) { instance_double(Process::Status, success?: true) }
  let(:clock) { instance_double(OpenLanes::Execution::Clock, remaining: 600) }
  let(:snapshot) { OpenLanes::Execution::Boundary::Snapshot.new(head: "abc123", remotes: {}, reflogs: {}) }
  let(:launcher) { instance_double(executor::Launcher, launch: child, start_clock: clock) }
  let(:invocations) { instance_double(executor::Invocation) }
  let(:supervision) { instance_double(executor::Supervision, supervise: status) }
  let(:verdict) { instance_double(executor::Verdict, judge: :judged) }
  let(:preferences) { instance_double(executor::Preferences, timeout_for: 1800, profile_for: profile) }
  let(:crew) { executor::Crew.new(launcher:, invocations:, supervision:, verdict:, preferences:, trace_dir: traces) }
  let(:records) { [] }

  before do
    allow(OpenLanes::Execution::Boundary).to receive(:snapshot).with(traces).and_return(snapshot)
    allow(executor::JournalHold).to receive_messages(forget: nil, hold: nil)
    allow(invocations).to receive(:first) { |_attempt, asked| ["claude", "--resume", asked.resume.to_s] }
    handle.on_restart = ->(fields) { records << fields }
  end

  after do
    OpenLanes::Execution::Control.reset!
    FileUtils.rm_rf(traces)
  end

  def run(asked = request) = first_start.call(attempt, asked, started)

  it "answers with the verdict, judged against the snapshot taken before the launch" do
    expect(run).to eq(:judged)
    expect(verdict).to have_received(:judge).with(have_attributes(clock:), status, before: snapshot, started:)
  end

  it "registers the control file under the plan and agent, and fills in the handle" do
    run
    expect(handle.control).to start_with(File.join(traces, "control-001.00-backend-coder-"))
    expect(File.exist?(handle.control)).to be(true)
    expect(handle.trace).to eq(attempt.trace)
    expect(handle.label.to_h.slice(:plan, :agent)).to eq(plan: "001.00", agent: "backend-coder")
  end

  it "hands the argv the control file was registered for to the launcher" do
    run
    expect(invocations).to have_received(:first).with(attempt, have_attributes(control: handle.control, round: 2))
    expect(launcher).to have_received(:launch).with(["claude", "--resume", ""], attempt)
  end

  it "arms the agent's clock and writes down what a restarted engine needs" do
    run
    expect(launcher).to have_received(:start_clock).with(handle, seconds: 1800)
    expect(records.last.except(:deadline)).to eq(cwd: traces, trace: attempt.trace, control: handle.control, before: snapshot.to_h)
    expect(Time.iso8601(records.last.fetch(:deadline))).to be_within(5).of(Time.now + 600)
  end

  it "supervises with the clock on the attempt" do
    run
    expect(supervision).to have_received(:supervise).with(child, have_attributes(clock:), an_instance_of(executor::Restarts))
  end

  it "notes which session holds the journal once the round is over" do
    run
    expect(executor::JournalHold).to have_received(:hold).with(have_attributes(handle:, sessions:))
    expect(executor::JournalHold).not_to have_received(:forget)
  end

  context "when the round is a rebase" do
    it "leaves the journal record alone" do
      run(request.with(rebase: "a conflict"))
      expect(executor::JournalHold).not_to have_received(:hold)
    end
  end

  context "when a session is resumed" do
    let(:resumed) { request.with(resume: "sess-1") }

    it "clears the record only after the prompt is cut to what the session lacks" do
      order = []
      allow(invocations).to receive(:first) { order << :prompt; %w[claude] }
      allow(executor::JournalHold).to receive(:forget) { order << :forget }
      run(resumed)
      expect(order).to eq(%i[prompt forget])
      expect(executor::JournalHold).to have_received(:forget).with(agent, subject_plan)
    end

    it "drops the session on a CLI that cannot resume one" do
      unresuming = OpenLanes::Adapters.names.map { OpenLanes::Adapters.for(it) }.find { !it.resumes? }
      skip "every adapter resumes" unless unresuming
      first_start.call(attempt.with(profile: profile.with(adapter: unresuming)), resumed, started)
      expect(invocations).to have_received(:first).with(anything, have_attributes(resume: nil))
      expect(executor::JournalHold).not_to have_received(:forget)
    end
  end

  describe "the ways a session is started again" do
    let(:restarts) { run(asked) && supervision_restarts }

    def supervision_restarts
      got = nil
      expect(supervision).to have_received(:supervise) { |_child, _attempt, given| got = given }
      got
    end

    context "without a session to resume" do
      let(:asked) { request }

      it "relaunches afresh, forgetting the session, and starts again the same way" do
        handle.session = "sess-1"
        expect(restarts.resume).to be_nil
        restarts.relaunch.call
        expect(handle.session).to be_nil
        expect(restarts.again).to equal(restarts.relaunch)
        expect(launcher).to have_received(:launch).with(["claude", "--resume", ""], attempt).twice
      end
    end

    context "when another model was chosen after the round began" do
      let(:asked) { request }
      let(:chosen) { profile.with(model: "claude-opus-4-1") }

      it "builds the relaunch's argv from the profile as it is now, and launches the same attempt" do
        allow(preferences).to receive(:profile_for).with(agent, subject_plan, root: traces).and_return(chosen)
        restarts.relaunch.call
        expect(invocations).to have_received(:first).with(have_attributes(profile: chosen), have_attributes(resume: nil))
        expect(launcher).to have_received(:launch).with(["claude", "--resume", ""], attempt).twice
      end
    end

    context "with a session to resume" do
      let(:asked) { request.with(resume: "sess-1") }

      it "starts again with the same argv, and relaunches without the session" do
        restarts.again.call
        restarts.relaunch.call
        expect(restarts.resume).to eq("sess-1")
        expect(launcher).to have_received(:launch).with(["claude", "--resume", "sess-1"], attempt).twice
        expect(launcher).to have_received(:launch).with(["claude", "--resume", ""], attempt).once
      end
    end
  end
end
