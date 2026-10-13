# frozen_string_literal: true

# A person compacts a running agent from the page (W28). `/compact` is the
# caller's command, so the harness stops the agent, sends `/compact` into its
# session with `--resume`, and carries the session on, all under one handle.
# The fake spawn below plays back each of the three processes in turn and
# keeps every argv, so nothing here starts `claude`.
RSpec.describe OpenLanes::Execution::Executor, :tree do
  subject(:result) { executor.call(agent, plan, handle:) }

  let(:executor) { described_class.new(root:, spawn:, trace_dir: traces, model: "sonnet") }
  let(:root) { File.dirname(plans_root) }
  let(:traces) { File.join(root, "traces") }
  let(:agent) { OpenLanes::Agents.find("luke-backend") }
  let(:spec_md) { spec_body }
  let(:plan) do
    plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_md, "plan.md" => "## Task\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end
  let(:handle) { described_class::Handle.new }
  let(:spawned) { [] }
  let(:controls) { [] }
  let(:requests) { [] }
  let(:switch_to) { nil }
  let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:broken) { instance_double(Process::Status, success?: false, exitstatus: 1) }
  let(:init) { event(type: "system", subtype: "init", session_id: "sess-1") }
  let(:boundary) do
    event(type: "system",
      subtype: "compact_boundary",
      session_id: "sess-1",
      compact_metadata: { trigger: "manual", pre_tokens: 46_599, post_tokens: 7240 })
  end
  # What the person's command does while the agent is at work.
  let(:during_agent) { -> { requests << handle.compact!(model: switch_to, grace: 0) } }
  let(:during_compact) { nil }
  let(:agent_stream) { [init, delta(100, 10)] }
  let(:compact_stream) { [init, boundary, delta(40, 4)] }
  let(:compact_status) { ok }
  let(:continue_stream) { [init, delta(20, 2)] }
  let(:spawn) do
    lambda do |argv, **|
      spawned << argv
      controls << File.read(handle.control)
      case spawned.size
      when 1 then child(agent_stream, during: during_agent)
      when 2 then child(compact_stream, status: compact_status, during: during_compact)
      else child(continue_stream)
      end
    end
  end
  let(:compaction) { requests.first }
  let(:compact_argv) { spawned[1] }
  let(:continue_argv) { spawned[2] }

  def event(hash) = "#{JSON.generate(hash)}\n"

  def delta(sent, made) = event(type: "stream_event", event: { type: "message_delta", usage: { input_tokens: sent, output_tokens: made } })

  def child(chunks, status: ok, during: nil)
    child = instance_double(OpenLanes::Execution::Child, pid: 100 + spawned.size, alive?: false, kill: nil, terminate: nil, wait: status)
    allow(child).to receive(:each_chunk) do |&block|
      chunks.each { block.call(it) }
      during&.call
    end
    child
  end

  after { OpenLanes::Execution::Control.reset! }

  context "when the agent named its session" do
    before { result }

    it "runs three processes: the agent, /compact, and the continuation" do
      expect(spawned.size).to eq(3)
    end

    it "asks the agent to stop with INTERRUPT, and clears that before it carries on" do
      expect([File.exist?(handle.control), controls]).to eq([false, ["", "INTERRUPT\n", ""]])
    end

    it "sends /compact into the same session, on the same model, with slash commands left on" do
      aggregate_failures do
        expect(compact_argv.first(3)).to eq(["claude", "-p", "/compact"])
        expect(compact_argv.each_cons(2).to_a).to include(%w[--resume sess-1], %w[--model sonnet])
        expect(compact_argv).to include("--strict-mcp-config")
        expect(compact_argv).not_to include("--disable-slash-commands")
      end
    end

    it "carries the session on with the continuation prompt, lean as before" do
      aggregate_failures do
        expect(continue_argv[2]).to include("Your context was just compacted", "Your control file is still #{handle.control}")
        expect(continue_argv.each_cons(2).to_a).to include(%w[--resume sess-1], %w[--model sonnet])
        expect(continue_argv).to include("--disable-slash-commands")
      end
    end

    it "answers the request once the continuation has started" do
      expect(compaction.to_h).to include(status: "done", reason: "luke-backend compacted from 46599 to 7240 tokens and carries on")
    end

    it "reports one invocation, spending what all three spent" do
      expect(result).to have_attributes(ok: true, up: 160, down: 16, pid: 103)
    end

    it "remembers the session on the handle" do
      expect(handle.session).to eq("sess-1")
    end
  end

  context "when a person switched the model" do
    let(:switch_to) { "claude-haiku-5-5" }

    before { result }

    it "compacts and carries on in the new model" do
      aggregate_failures do
        expect([compact_argv, continue_argv].map { it.each_cons(2).to_a }).to all(include(%w[--model claude-haiku-5-5]))
        expect(compaction.reason).to end_with("carries on on claude-haiku-5-5")
      end
    end
  end

  describe "the meter" do
    let(:seen) { [] }

    before { executor.call(agent, plan, handle:) { seen << it.up } }

    it "counts the continuation on top of what the agent had spent" do
      expect(seen.last).to eq(160)
    end
  end

  context "when the agent never named its session" do
    let(:agent_stream) { [delta(100, 10)] }

    before { result }

    it "refuses, starts nothing more, and gives the agent its round back" do
      aggregate_failures do
        expect(spawned.size).to eq(1)
        expect(compaction.to_h).to include(status: "refused", restart: true)
        expect(compaction.reason).to eq("could not compact luke-backend: no session id to resume; " \
                                        "it restarts from its resume note in a fresh session")
      end
    end
  end

  context "when /compact compacts nothing" do
    let(:compact_stream) { [init, event(type: "result", result: "/compact isn't available in this environment.")] }

    before { result }

    it "refuses with what claude said, and carries nothing on" do
      aggregate_failures do
        expect(spawned.size).to eq(2)
        expect(compaction.reason).to include("/compact did not compact")
        expect(compaction.restart).to be(true)
      end
    end
  end

  context "when /compact exits non-zero" do
    let(:compact_status) { broken }

    before { result }

    it "refuses, saying so" do
      expect(compaction.reason).to start_with("could not compact luke-backend: /compact exited 1")
    end
  end

  context "when /compact reports an error" do
    let(:compact_stream) { [init, event(type: "result", is_error: true, result: "rate limited")] }

    before { result }

    it "refuses with the error" do
      expect(compaction.reason).to start_with("could not compact luke-backend: /compact reported: rate limited")
    end
  end

  context "when the agent is killed during /compact" do
    let(:during_compact) { -> { handle.kill!(grace: 0, reason: :key) } }

    before { result }

    it "refuses, gives no round back, and reports the kill" do
      aggregate_failures do
        expect(compaction.to_h).to include(status: "refused", restart: false)
        expect(result).to have_attributes(ok: false, killed: :key)
      end
    end
  end

  context "when the agent was killed before its compaction" do
    let(:during_agent) do
      lambda {
        handle.kill!(grace: 0, reason: :discard)
        requests << handle.compact!(grace: 0)
      }
    end

    before { result }

    it "refuses without restarting it" do
      expect(compaction.to_h).to include(status: "refused",
        restart: false,
        reason: "luke-backend was stopped first (discard)")
    end
  end

  context "when the agent is on a CLI that cannot resume" do
    let(:spec_md) { "---\nphases:\n  building: { adapter: codex }\n---\n#{spec_body}" }
    let(:agent) { OpenLanes::Agents.find("luke-backend").with(phase: "building") }

    before { result }

    it "refuses, naming the CLI" do
      expect(compaction.reason).to start_with("could not compact luke-backend: codex cannot resume a session")
    end
  end

  context "when the continuation cannot even be started" do
    let(:spawn) do
      lambda do |argv, **|
        spawned << argv
        raise Errno::ENOENT, "claude" if spawned.size == 3

        spawned.size == 1 ? child(agent_stream, during: during_agent) : child(compact_stream)
      end
    end

    let(:raised) { [] }

    before do
      result
    rescue StandardError => e
      raised << e
    end

    it "lets the error go on up" do
      expect(raised.map(&:class)).to eq([Errno::ENOENT])
    end

    it "refuses the request before the error goes on up" do
      expect(compaction.to_h).to include(status: "refused", reason: start_with("could not compact luke-backend: No such file"))
    end

    it "still releases the control file" do
      expect(File.exist?(handle.control)).to be(false)
    end
  end

  describe OpenLanes::Execution::Executor::Handle do
    subject(:handle) { described_class.new }

    it "hands the same request to a second ask while the first is under way" do
      handle.compact!(grace: 0)
      expect(handle.compact!(model: "opus", grace: 0)).to have_attributes(model: nil, status: nil).and be(handle.compaction)
    end

    it "hands a request out once" do
      handle.compact!(grace: 0)
      expect([handle.take_compaction, handle.take_compaction].map(&:class)).to eq([OpenLanes::Execution::Executor::Compaction, NilClass])
    end

    it "refuses a request that arrives after the invocation ended" do
      handle.close!
      expect(handle.compact!(grace: 0).to_h).to include(status: "refused", reason: "the agent finished before it could be compacted")
    end

    it "refuses a request the invocation ended before acting on" do
      handle.compact!(grace: 0)
      handle.close!
      expect(handle.compaction.reason).to eq("the agent finished before it could be compacted")
    end

    context "with an agent that will not stop" do
      let(:process) { instance_double(OpenLanes::Execution::Child, alive?: true, kill: nil, terminate: nil) }

      before do
        handle.child = process
        handle.compact!(grace: 0)
        sleep 0.05
      end

      it "kills it once the grace is spent" do
        expect(process).to have_received(:terminate)
      end
    end

    # The executor may move on to /compact the moment the request is visible,
    # so the INTERRUPT and the kill timer are aimed at the process that was
    # running when it was asked, never at the one that replaced it.
    context "when the agent is replaced while the request is being made" do
      let(:first) { instance_double(OpenLanes::Execution::Child, alive?: true, kill: nil, terminate: nil) }
      let(:replacement) { instance_double(OpenLanes::Execution::Child, alive?: true, kill: nil, terminate: nil) }
      let(:visible) { [] }

      before do
        handle.child = first
        handle.control = OpenLanes::Execution::Control.register(Dir.mktmpdir, "001.00-luke")
        allow(OpenLanes::Execution::Control).to receive(:write).and_wrap_original do |original, *args|
          visible << handle.instance_variable_get(:@requested)
          handle.child = replacement
          original.call(*args)
        end
        allow(Thread).to receive(:new).and_yield
        handle.compact!(grace: 0)
      end

      it "writes the INTERRUPT before the request can be taken" do
        expect(visible).to eq([nil])
      end

      it "never kills the replacement" do
        expect(replacement).not_to have_received(:terminate)
      end
    end
  end
end
