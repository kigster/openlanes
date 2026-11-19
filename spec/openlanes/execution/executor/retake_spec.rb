# frozen_string_literal: true

# An agent an earlier engine started and did not see end, taken back over a
# crew of doubles: the process attached, the trace read from the start, the
# clock rearmed from the record, and the verdict judged against the snapshot
# that record holds.
RSpec.describe OpenLanes::Execution::Executor::Retake do
  subject(:retake) { described_class.new(crew) }

  let(:executor) { OpenLanes::Execution::Executor }
  let(:dir) { Dir.mktmpdir("retake") }
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:subject_plan) { Struct.new(:feature).new(Struct.new(:ordinal).new("001.00")) }
  let(:profile) { OpenLanes::Agents::Profile.new(adapter: OpenLanes::Adapters.for("claude"), model: nil, effort: nil) }
  let(:handle) { executor::Handle.new }
  let(:trace) { File.join(dir, "t.ndjson").tap { File.write(it, "stale line\n") } }
  let(:attempt) do
    executor::Attempt.new(agent:, subject: subject_plan, root: dir, profile:, trace:, handle:, sessions: executor::Sessions.new)
  end
  let(:control) { File.join(dir, "control-001.00-backend-coder") }
  let(:before) { { "head" => "abc123", "remotes" => { "refs/remotes/origin/main" => "def456" }, "reflogs" => { "refs/remotes/origin/main" => 3 } } }
  let(:restart) do
    { "process" => { "pid" => 4242 }, "cwd" => dir, "trace" => trace, "control" => control, "before" => before,
      "deadline" => (Time.now + 600).utc.iso8601 }
  end
  let(:started) { OpenLanes::UI.monotonic }

  let(:process) { instance_double(OpenLanes::Execution::AgentProcess) }
  let(:child) { instance_double(OpenLanes::Execution::AgentProcess) }
  let(:status) { instance_double(Process::Status, success?: true) }
  let(:clock) { instance_double(OpenLanes::Execution::Clock, remaining: 540) }
  let(:launcher) { instance_double(executor::Launcher, follow: child, rearm: 540, start_clock: clock) }
  let(:supervision) { instance_double(executor::Supervision, supervise: status) }
  let(:verdict) { instance_double(executor::Verdict, judge: :judged) }
  let(:preferences) { instance_double(executor::Preferences, timeout_for: 1800) }
  let(:crew) do
    executor::Crew.new(launcher:, invocations: instance_double(executor::Invocation), supervision:, verdict:, preferences:, trace_dir: dir)
  end
  let(:records) { [] }

  before do
    allow(OpenLanes::Execution::AgentProcess).to receive(:attach).with(restart.fetch("process")).and_return(process)
    handle.on_restart = ->(fields) { records << fields }
  end

  after do
    OpenLanes::Execution::Control.reset!
    FileUtils.rm_rf(dir)
  end

  def run = retake.call(attempt, restart, started)

  it "answers with the verdict, judged against the snapshot the record holds" do
    expect(run).to eq(:judged)
    snapshot = OpenLanes::Execution::Boundary::Snapshot.new(**before.transform_keys(&:to_sym))
    expect(verdict).to have_received(:judge).with(have_attributes(clock:), status, before: snapshot, started:)
  end

  it "follows the recorded process rather than starting one" do
    run
    expect(launcher).to have_received(:follow).with(process, attempt)
    expect(supervision).to have_received(:supervise).with(child, have_attributes(clock:))
  end

  it "reads the trace again from the start" do
    run
    expect(File.read(trace)).to eq("")
    expect(handle.trace).to eq(trace)
  end

  it "takes the control file back, creating it when the earlier engine's is gone" do
    run
    expect(handle.control).to eq(control)
    expect(File.exist?(control)).to be(true)
    expect(handle.label.to_h.slice(:plan, :agent, :control)).to eq(plan: "001.00", agent: "backend-coder", control:)
  end

  it "rearms the clock from the record, within the agent's budget, and writes the deadline down" do
    run
    expect(launcher).to have_received(:rearm).with(agent, restart, budget: 1800)
    expect(launcher).to have_received(:start_clock).with(handle, seconds: 540)
    expect(records.map(&:keys)).to eq([[:deadline]])
    expect(Time.iso8601(records.last.fetch(:deadline))).to be_within(5).of(Time.now + 540)
  end
end
