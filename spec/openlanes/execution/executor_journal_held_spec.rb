# frozen_string_literal: true

# Plan 062.00: the executor records what a round's session holds of the
# journal when the round ends with that session intact, and drops the record
# when a round resumes it, so only a round that ended cleanly is ever trusted
# to have left the earlier entries in the session. The fake spawn plays back
# each process in turn and keeps every argv, so nothing here starts `claude`.
RSpec.describe OpenLanes::Execution::Executor, :tree do
  subject(:result) { executor.call(agent, plan, handle:, resume:) }

  let(:executor) { described_class.new(root:, spawn:, trace_dir: traces) }
  let(:root) { File.dirname(plans_root) }
  let(:traces) { File.join(root, "traces") }
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:plan) do
    plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end
  let(:state) { OpenLanes::Plans::PlanState.for(plan.feature.path) }
  let(:handle) { described_class::Handle.new }
  let(:resume) { "sess-1" }
  let(:spawned) { [] }
  let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:broken) { instance_double(Process::Status, success?: false, exitstatus: 1) }
  let(:init) { event(type: "system", subtype: "init", session_id: "sess-1") }
  let(:streams) { [[[init, delta(100, 10)], ok]] }
  let(:spawn) do
    lambda do |argv, **|
      spawned << argv
      chunks, status = streams.fetch(spawned.size - 1)
      child(chunks, status)
    end
  end
  let(:entry) { OpenLanes::Plans::Journal::Entry }

  def event(hash) = "#{JSON.generate(hash)}\n"

  def delta(sent, made) = event(type: "stream_event", event: { type: "message_delta", usage: { input_tokens: sent, output_tokens: made } })

  def child(chunks, status)
    child = instance_double(OpenLanes::Execution::Child, pid: 100 + spawned.size, alive?: false, kill: nil, terminate: nil, wait: status)
    allow(child).to receive(:each_chunk) { |&block| chunks.each { block.call(it) } }
    child
  end

  def note(*texts) = state.journal!(agent: "backend-coder", entries: texts.map { entry.new(kind: "note", text: it) })

  before { note("one", "two") }

  after { OpenLanes::Execution::Control.reset! }

  context "when a fresh round ends with its session intact" do
    let(:resume) { nil }

    before { result }

    it "sends the whole journal" do
      expect(spawned.first[2]).to include("the moment it happens", "1. [note] one", "2. [note] two")
    end

    it "records that the session holds it" do
      expect(state.held("backend-coder").to_h).to eq(session: "sess-1", through: 2)
    end
  end

  context "when the round resumes the session the last one recorded" do
    before do
      state.hold!(agent: "backend-coder", session: "sess-1")
      note("three")
      result
    end

    it "sends only the entries written since" do
      aggregate_failures do
        expect(spawned.first[2]).to include("## Your journal - carry on", "3. [note] three")
        expect(spawned.first[2]).not_to include("[note] one", "the moment it happens")
      end
    end

    it "records the session again, now holding those too" do
      expect(state.held("backend-coder").to_h).to eq(session: "sess-1", through: 3)
    end
  end

  context "when the round resumes a session no round vouched for" do
    before { result }

    it "sends the whole journal" do
      expect(spawned.first[2]).to include("the moment it happens", "1. [note] one")
    end
  end

  context "when the CLI cannot find the session and the round starts again fresh" do
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
    let(:streams) { [[missing, broken], [[event(type: "system", subtype: "init", session_id: "sess-2"), delta(50, 5)], ok]] }

    before do
      state.hold!(agent: "backend-coder", session: "sess-1")
      result
    end

    it "sends the fresh session the whole journal" do
      expect([spawned.first[2].include?("[note] one"), spawned.last[2].include?("1. [note] one")]).to eq([false, true])
    end

    it "records the fresh session as the one that holds it" do
      expect(state.held("backend-coder").to_h).to eq(session: "sess-2", through: 2)
    end
  end

  # The CLI compacts at its own threshold without being asked, and says so
  # with the same event a person's `/compact` produces.
  context "when the session was compacted during the round" do
    let(:boundary) do
      event(type: "system", subtype: "compact_boundary", session_id: "sess-1", compact_metadata: { trigger: "auto", pre_tokens: 80_000, post_tokens: 9000 })
    end
    let(:streams) { [[[init, delta(100, 10), boundary, delta(20, 2)], ok]] }

    before do
      state.hold!(agent: "backend-coder", session: "sess-1")
      result
    end

    it "leaves no record, so the next round is sent the whole journal" do
      expect([result.ok, state.held("backend-coder")]).to eq([true, nil])
    end
  end

  context "when the round only resolves a rebase" do
    let(:resume) { nil }
    let(:rebase) { OpenLanes::Vcs::Refresh::Outcome.new(kind: :conflicted, base: "origin/main", files: ["lib/a.rb"]) }

    before do
      state.hold!(agent: "backend-coder", session: "sess-0")
      executor.call(agent, plan, handle:, rebase:)
    end

    it "leaves the record of the plan's own session alone" do
      expect(state.held("backend-coder").to_h).to eq(session: "sess-0", through: 2)
    end
  end
end
