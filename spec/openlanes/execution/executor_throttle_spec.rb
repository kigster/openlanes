# frozen_string_literal: true

# Plan 060.00, item 4: an invocation that ends on its provider's rate limit
# or overload waits and starts again inside the one attempt. The fake spawn
# plays back each process in turn, and the backoff is handed a sleep that
# returns at once, so nothing here starts `claude` or waits.
RSpec.describe OpenLanes::Execution::Executor, :tree do
  subject(:result) { executor.call(agent, plan, handle:, resume:) { |progress| shown << progress.activity } }

  let(:executor) { described_class.new(root:, spawn:, trace_dir: traces, throttle:) }
  let(:throttle) do
    OpenLanes::Execution::Throttle::Backoff.new(random: instance_double(Random, rand: 0.0), sleep:, **limits)
  end
  let(:sleep) { ->(seconds) { slept << seconds } }
  let(:limits) { {} }
  let(:slept) { [] }
  let(:shown) { [] }
  let(:root) { File.dirname(plans_root) }
  let(:traces) { File.join(root, "traces") }
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:plan) do
    plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end
  let(:handle) { described_class::Handle.new }
  let(:resume) { nil }
  let(:spawned) { [] }
  let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:broken) { instance_double(Process::Status, success?: false, exitstatus: 1) }
  let(:init) { event(type: "system", subtype: "init", session_id: "sess-1") }
  let(:limited) { [init, failed_with("API Error: 429 rate_limit_error. retry-after: 20")] }
  let(:working) { [init, delta(100, 10)] }
  let(:heard) { [] }
  let!(:tap) { OpenLanes::UI.tap_log(->(message, _) { heard << message }) }
  let(:spawn) do
    lambda do |argv, **|
      spawned << argv
      chunks, status = streams.fetch(spawned.size - 1)
      child(chunks, status)
    end
  end

  def event(hash) = "#{JSON.generate(hash)}\n"

  def delta(sent, made) = event(type: "stream_event", event: { type: "message_delta", usage: { input_tokens: sent, output_tokens: made } })

  def failed_with(text, sent: 0, made: 0)
    event(type: "result",
      subtype: "error_during_execution",
      is_error: true,
      result: text,
      session_id: "sess-1",
      usage: { input_tokens: sent, output_tokens: made })
  end

  def child(chunks, status)
    child = instance_double(OpenLanes::Execution::Child, pid: 100 + spawned.size, alive?: false, kill: nil, terminate: nil, wait: status)
    allow(child).to receive(:each_chunk) { |&block| chunks.each { block.call(it) } }
    child
  end

  def pairs(argv) = argv.each_cons(2).to_a

  after do
    OpenLanes::UI.untap_log(tap)
    OpenLanes::Execution::Control.reset!
  end

  context "when a fresh start is rate limited before spending anything" do
    let(:streams) { [[limited, broken], [working, ok]] }

    before { result }

    it "waits as the provider asked, then starts again as it started" do
      aggregate_failures do
        expect(slept.sum).to eq(20)
        expect(spawned.size).to eq(2)
        expect(spawned.last).to eq(spawned.first)
      end
    end

    it "is one attempt, and it succeeded" do
      expect([result.ok, result.throttled, result.up]).to eq([true, false, 100])
    end

    it "says in the log that it is waiting, and for what" do
      expect(heard).to include(a_string_matching(/\Abackend-coder rate limited, retry 1 of 8 in 20s \(API Error: 429/))
    end
  end

  context "when a session that was working meets an overload" do
    let(:streams) do
      [[[init, delta(100, 10), failed_with("API Error: Repeated 529 Overloaded errors", sent: 100, made: 10)], broken],
       [working, ok]]
    end

    before { result }

    it "carries the same session on, told why it was paused" do
      aggregate_failures do
        expect(slept.sum).to eq(30)
        expect(pairs(spawned.last)).to include(%w[--resume sess-1])
        expect(spawned.last.join(" ")).to include("was overloaded when it got your last request")
      end
    end

    it "shows the wait over the agent's own line on the board" do
      expect(shown).to include("provider overloaded, retry 1 of 8 in 30s")
    end

    it "adds up what both sessions spent" do
      expect([result.ok, result.up]).to eq([true, 200])
    end
  end

  context "when a resumed session is rate limited before spending anything" do
    let(:resume) { "sess-1" }
    let(:streams) { [[limited, broken], [working, ok]] }

    before { result }

    it "keeps the session, where a lost one would have been started fresh" do
      aggregate_failures do
        expect(pairs(spawned.last)).to include(%w[--resume sess-1])
        expect(heard.grep(/starting backend-coder fresh/)).to be_empty
      end
    end
  end

  context "when the limit never lifts" do
    let(:limits) { { attempts: 2 } }
    let(:streams) { Array.new(3) { [limited, broken] } }

    before { result }

    it "stops after its retries" do
      expect(spawned.size).to eq(3)
    end

    it "fails naming the limit, not the agent" do
      expect([result.ok, result.throttled, result.note])
        .to match([false, true, a_string_starting_with("rate limited: gave up after 2 retries and 40s of waiting")])
    end
  end

  context "when the agent is stopped while it waits" do
    let(:streams) { [[limited, broken]] }
    let(:sleep) do
      lambda do |seconds|
        slept << seconds
        handle.request_stop!
      end
    end

    before { result }

    it "is not started again" do
      expect([spawned.size, slept.size]).to eq([1, 1])
    end

    it "says it was stopped while waiting" do
      expect(result.note).to start_with("rate limited: stopped while waiting to retry")
    end
  end

  context "when the invocation fails at something else" do
    let(:streams) { [[[init, failed_with("401 API key is invalid")], broken]] }

    before { result }

    it "is not waited on" do
      expect([spawned.size, slept, result.ok, result.throttled]).to eq([1, [], false, false])
    end
  end
end
