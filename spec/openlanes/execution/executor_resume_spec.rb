# frozen_string_literal: true

# M1: the executor carries the previous round's session on when it is handed
# one, and starts fresh, once, when the CLI says that session does not exist.
# The fake spawn plays back each process in turn and keeps every argv, so
# nothing here starts `claude`.
RSpec.describe OpenLanes::Execution::Executor, :tree do
  subject(:result) { executor.call(agent, plan, handle:, resume:) }

  let(:executor) { described_class.new(root:, spawn:, trace_dir: traces) }
  let(:root) { File.dirname(plans_root) }
  let(:traces) { File.join(root, "traces") }
  let(:agent) { OpenLanes::Agents.find("luke-backend") }
  let(:plan) do
    plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end
  let(:handle) { described_class::Handle.new }
  let(:resume) { "sess-1" }
  let(:spawned) { [] }
  let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:broken) { instance_double(Process::Status, success?: false, exitstatus: 1) }
  let(:streams) { [[[event(type: "system", subtype: "init", session_id: "sess-1"), delta(100, 10)], ok]] }
  let(:spawn) do
    lambda do |argv, **|
      spawned << argv
      chunks, status = streams.fetch(spawned.size - 1)
      child(chunks, status)
    end
  end
  let(:missing) do
    ["No conversation found with session ID: sess-1\n",
     event(type: "result",
       subtype: "error_during_execution",
       is_error: true,
       num_turns: 0,
       session_id: "sess-1",
       errors: ["No conversation found with session ID: sess-1"],
       usage: { input_tokens: 0, output_tokens: 0 })]
  end
  let(:fresh_stream) { [event(type: "system", subtype: "init", session_id: "sess-2"), delta(50, 5)] }

  def event(hash) = "#{JSON.generate(hash)}\n"

  def delta(sent, made) = event(type: "stream_event", event: { type: "message_delta", usage: { input_tokens: sent, output_tokens: made } })

  def child(chunks, status)
    child = instance_double(OpenLanes::Execution::Child, pid: 100 + spawned.size, alive?: false, kill: nil, terminate: nil, wait: status)
    allow(child).to receive(:each_chunk) { |&block| chunks.each { block.call(it) } }
    child
  end

  def pairs(argv) = argv.each_cons(2).to_a

  after { OpenLanes::Execution::Control.reset! }

  context "when handed a session that exists" do
    before { result }

    it "resumes it, with this round's own prompt" do
      aggregate_failures do
        expect(spawned.size).to eq(1)
        expect(pairs(spawned.first)).to include(%w[--resume sess-1])
        expect(spawned.first[2]).to include("luke-backend")
      end
    end

    it "keeps the session on the handle" do
      expect([result.ok, handle.session]).to eq([true, "sess-1"])
    end
  end

  context "when handed no session" do
    let(:resume) { nil }

    before { result }

    it "starts fresh" do
      expect(spawned.first).not_to include("--resume")
    end
  end

  context "when the CLI cannot find the session" do
    let(:streams) { [[missing, broken], [fresh_stream, ok]] }

    before { result }

    it "starts once more, fresh" do
      aggregate_failures do
        expect(spawned.size).to eq(2)
        expect(pairs(spawned.first)).to include(%w[--resume sess-1])
        expect(spawned.last).not_to include("--resume")
      end
    end

    it "reports the fresh run and its session" do
      expect([result.ok, result.up, handle.session]).to eq([true, 50, "sess-2"])
    end
  end

  context "when a resumed run fails having spent nothing, without the usual message" do
    let(:streams) { [[["something went wrong\n"], broken], [fresh_stream, ok]] }

    before { result }

    it "takes it as the same thing and starts fresh" do
      expect([spawned.size, result.ok]).to eq([2, true])
    end
  end

  context "when a resumed run fails after doing work" do
    let(:streams) { [[[event(type: "system", subtype: "init", session_id: "sess-1"), delta(100, 10)], broken]] }

    before { result }

    it "does not start again: the failure is the round's own" do
      expect([spawned.size, result.ok]).to eq([1, false])
    end
  end

  context "when a fresh run fails having spent nothing" do
    let(:resume) { nil }
    let(:streams) { [[missing, broken]] }

    before { result }

    it "does not retry, since there was no session to drop" do
      expect([spawned.size, result.ok]).to eq([1, false])
    end
  end

  context "when the agent runs on a CLI that cannot resume" do
    let(:agent) { OpenLanes::Agents.find("luke-backend").with(adapter: "codex") }
    let(:streams) { [[[], ok]] }

    before { result }

    it "starts fresh whatever it was handed" do
      expect(spawned.first.join(" ")).not_to include("sess-1")
    end
  end
end
