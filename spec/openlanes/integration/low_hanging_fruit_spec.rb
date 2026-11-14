# frozen_string_literal: true

# 060.00 B6a: unit sizing and the pre-review gate end to end. A real
# `.plans` tree, a real Runner and dispatcher, and a real Executor asked for
# the builder's profile. The doubles are the house seams: the agent CLI
# (the executor's `call`), the publisher, and the gate's result, since a
# suite run inside this suite proves nothing about this suite.
RSpec.describe "Low-hanging fruit", :tree do
  before do
    root = File.dirname(plans_root)
    Dir.chdir(root)
    # Fable is reachable only through sizing:, so seeing it proves the
    # large profile was used.
    File.write(File.join(root, ".openlanes.yml"), "sizing:\n  large: { model: fable }\n")
    [calls, stamp]
    allow(publisher).to receive(:publish).and_return(publication)
    allow(OpenLanes::Engine::PreReviewGate).to receive(:call).and_return(red, green)
    plans { |t| t.plan "001.00", :building, "tic-tac-toe", files: }
  end

  let(:stamp) { "2026-09-04 11:29:20 AM PDT" }
  let(:calls) { [] }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:state) { OpenLanes::Engine::StateFile.new(path: OpenLanes::Engine::StateFile.for(tree)) }
  let(:files) do
    { "spec.md"          => "---\nstarts: building\n---\n#{spec_body}",
      "plan.md"          => "# Plan\n\n## Backend\n\n### B1 Board\n\n- **Size:** large\n\n## How to test\n\n- run it\n",
      "pull-requests.md" => "# Pull Requests\n" }
  end
  let(:checkout) do
    instance_double(OpenLanes::Vcs::Worktree::Checkout, branch: "kig/001.00-tic-tac-toe", path: plans_root, dirty?: true)
  end
  let(:worktree) { instance_double(OpenLanes::Vcs::Worktree, checkout_for: checkout, refresh: nil, root: File.dirname(plans_root)) }
  let(:publisher) { instance_double(OpenLanes::Vcs::Publisher) }
  let(:publication) do
    OpenLanes::Vcs::Publisher::Publication.new(ordinal: OpenLanes::Plans::Ordinal.parse("001.00"),
      branch:  checkout.branch,
      title:   "[001.00](A) Tic Tac Toe",
      url:     "https://github.com/example/repo/pull/12",
      refusal: nil)
  end
  let(:red) { OpenLanes::Engine::PreReviewGate::Verdict.new(passed: false, reason: "`just check-all` exited 1", log_tail: "1 failure\n") }
  let(:green) { OpenLanes::Engine::PreReviewGate::Verdict.new(passed: true, reason: "`just check-all` passed", log_tail: "") }

  # The agent CLI is faked; the profile comes from a real Executor, so the
  # sizing table, the plan.md read and Profile.resolve are all the real ones.
  let(:executor) do
    real = OpenLanes::Execution::Executor.new(root: File.dirname(plans_root))
    log = calls
    at = stamp
    Class.new do
      define_method(:profile_for) { |agent, subject = nil, **keywords| real.profile_for(agent, subject, **keywords) }
      define_method(:call) do |agent, subject, round: 1, **|
        log << agent.name
        file = File.join(subject.feature.path, agent.ledger.first)
        OpenLanes::Plans::Ledger.append(file, "> [#{at}] [ agent: #{agent.name}   status: Completed, round #{round} ]")
        OpenLanes::Execution::Executor::Result.new(ok: true, note: "completed", up: 10, down: 2, subagents: 0, delegated: 0, seconds: 1.0)
      end
    end.new
  end
  let(:attempts) do
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:     OpenLanes::Agents::Registry.new.only("chores-coder"),
      isolation:  :worktree,
      jobs:       1,
      worktree:,
      publisher:,
      state:,
      extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false),
      sleeper:    ->(_) {}).call
  end
  let(:plan) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")) }
  let(:models) { OpenLanes::Plans::PlanState.for(plan.feature.path).stages.filter_map { it["model"] } }
  let(:mail) { OpenLanes::Plans::Mailbox.new(dir: plan.feature.path).for("chores-coder") }

  it "starts a large unit on sizing.large, bounces a red build, and publishes the green one" do
    attempts
    aggregate_failures do
      expect(models).to eq(%w[fable fable])
      expect(calls).to eq(%w[chores-coder chores-coder])
      expect(attempts.first.note).to include("pre-review gate red")
      expect(mail.map(&:body)).to contain_exactly(include("No reviewer was started", "1 failure"))
      expect(publisher).to have_received(:publish).once
      expect(plan.status.key).to eq(:ready_for_review)
    end
  end

  # B6b, point 3: the agent CLI is a played-back stream under a real
  # Executor. The first process ends on a 429; the throttle waits (an
  # instant sleep here) and starts it again inside the same attempt.
  context "when the provider rate limits the build" do
    before do
      allow(OpenLanes::Engine::PreReviewGate).to receive(:call).and_return(green)
      # Memoised on the example's thread; the job thread reading them first
      # would wait on RSpec's memo lock that `attempts` holds.
      [spawned, slept, streams, ok]
    end

    let(:slept) { [] }
    let(:spawned) { [] }
    let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
    let(:broken) { instance_double(Process::Status, success?: false, exitstatus: 1) }
    let(:init) { event(type: "system", subtype: "init", session_id: "sess-1") }
    let(:limited) { [init, failed_with("API Error: 429 rate_limit_error. retry-after: 20")] }
    let(:working) { [init, event(type: "stream_event", event: { type: "message_delta", usage: { input_tokens: 100, output_tokens: 10 } })] }
    let(:streams) { [[limited, broken], [working, ok]] }
    let(:throttle) do
      OpenLanes::Execution::Throttle::Backoff.new(random: instance_double(Random, rand: 0.0), sleep: ->(seconds) { slept << seconds })
    end
    let(:executor) do
      root = File.dirname(plans_root)
      sign = method(:sign_completed)
      OpenLanes::Execution::Executor.new(root:,
        trace_dir: File.join(root, "traces"),
        throttle:,
        spawn: lambda { |argv, **|
          spawned << argv
          chunks, status = streams.fetch(spawned.size - 1)
          sign.call if status == ok
          child(chunks, status)
        })
    end

    after { OpenLanes::Execution::Control.reset! }

    def event(hash) = "#{JSON.generate(hash)}\n"

    def failed_with(text)
      event(type: "result",
        subtype: "error_during_execution",
        is_error: true,
        result: text,
        session_id: "sess-1",
        usage: { input_tokens: 0, output_tokens: 0 })
    end

    def child(chunks, status)
      child = instance_double(OpenLanes::Execution::Child, pid: 100 + spawned.size, alive?: false, kill: nil, terminate: nil, wait: status)
      allow(child).to receive(:each_chunk) { |&block| chunks.each { block.call(it) } }
      child
    end

    # What the agent would have written before it exited cleanly.
    def sign_completed
      subject = OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
      OpenLanes::Plans::Ledger.append(File.join(subject.feature.path, "plan.md"),
        "> [#{stamp}] [ agent: chores-coder   status: Completed, round 1 ]")
    end

    it "waits as asked, retries inside the one attempt, and goes on to review" do
      attempts
      aggregate_failures do
        expect([slept.sum, spawned.size]).to eq([20, 2])
        expect(attempts.size).to eq(1)
        expect(attempts.first).to have_attributes(ok: true, to: :ready_for_review)
        expect(publisher).to have_received(:publish).once
      end
    end
  end
end
