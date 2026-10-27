# frozen_string_literal: true

# B1 in plan 041: the executor takes back an agent an earlier engine
# started, from what that engine recorded, and settles it as its own. The
# agent supervisor is played by a double, so nothing here starts `claude`.
RSpec.describe OpenLanes::Execution::Executor, :tree do
  subject(:result) { executor.reattach(agent, plan, restart:, handle:) }

  let(:executor) { described_class.new(root:, trace_dir: traces) }
  let(:root) { File.dirname(plans_root) }
  let(:traces) { File.join(root, "traces") }
  let(:trace) { File.join(traces, "001.00-backend-coder.ndjson") }
  let(:control) { File.join(traces, "001.00-backend-coder.control") }
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:plan) do
    plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end
  let(:handle) { described_class::Handle.new }
  let(:deadline) { (Time.now + 600).utc.iso8601 }
  let(:before_run) { OpenLanes::Execution::Boundary.snapshot(root).to_h }
  let(:process) { { "pid" => 4242, "output" => "o", "status" => "s", "pid_file" => "p" } }
  let(:restart) do
    JSON.parse(JSON.generate(process:, cwd: root, trace:, control:, before: before_run, deadline:))
  end
  let(:status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:chunks) { [event(type: "system", subtype: "init", session_id: "sess-1"), event(type: "result", subtype: "success", is_error: false, result: "done", session_id: "sess-1")] }
  let(:child) do
    instance_double(OpenLanes::Execution::AgentProcess, pid: 4242, alive?: false, wait: status).tap do |child|
      allow(child).to receive(:each_chunk) { |&block| chunks.each { block.call(it) } }
      allow(child).to receive_messages(terminate: nil, kill: nil)
      allow(child).to receive(:restart).and_return(pid: 4242)
    end
  end

  def event(hash) = "#{JSON.generate(hash)}\n"

  before do
    FileUtils.mkdir_p(traces)
    File.write(trace, "what the dead engine's executor had written\n")
    allow(OpenLanes::Execution::AgentProcess).to receive(:attach).with(process).and_return(child)
  end

  after { OpenLanes::Execution::Control.reset! }

  context "with an agent that runs to the end" do
    it("settles it") { expect(result.ok).to be(true) }
    it("reads its session") { result && expect(handle.session).to(eq("sess-1")) }
    it("rebuilds the trace from the start") { result && expect(File.read(trace)).not_to(include("dead engine")) }
    it("names the plan and agent on the handle") { result && expect(handle.label.to_s).to(eq("001.00-backend-coder")) }
    it("names its control file on the handle's label") { result && expect(handle.label.control).to(eq(handle.control)) }
  end

  describe "its clock" do
    before do
      allow(OpenLanes::Execution::Clock).to receive(:new).and_call_original
      result
    end

    it("runs to the recorded deadline") { expect(OpenLanes::Execution::Clock).to have_received(:new).with(hash_including(seconds: be_within(5).of(600))) }

    context "with the deadline already past" do
      let(:deadline) { (Time.now - 60).utc.iso8601 }

      it("leaves it no time") { expect(OpenLanes::Execution::Clock).to have_received(:new).with(hash_including(seconds: 0)) }
    end
  end

  context "with an agent that committed while no engine watched" do
    let(:before_run) { { head: "0" * 40, remotes: {}, reflogs: {} } }

    it("refuses it") { expect(result).to have_attributes(ok: false, note: /agent committed/) }
  end

  describe "a deadline an extension moved" do
    let(:recorded) { [] }
    let(:clock) { OpenLanes::Execution::Clock.new(seconds: 60, control: control, on_expire: -> {}) }

    before do
      handle.on_restart = ->(fields) { recorded << fields }
      handle.clock = clock
      handle.extend!(600)
    end

    it("is recorded for the next engine") { expect(Time.iso8601(recorded.last[:deadline])).to be_within(5).of(Time.now + 660) }
  end
end
