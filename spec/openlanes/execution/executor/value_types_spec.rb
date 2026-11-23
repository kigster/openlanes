# frozen_string_literal: true

RSpec.describe "the executor's value types" do
  describe OpenLanes::Execution::Executor::Result do
    subject(:result) { described_class.new(ok: true, note: "completed", up: 10, down: 2, subagents: 0, delegated: 0, seconds: 1.0) }

    it "defaults what an invocation did not say" do
      expect(result.to_h.slice(:killed, :pid, :cached, :throttled)).to eq(killed: nil, pid: nil, cached: 0, throttled: false)
    end

    it "lets a caller say them" do
      expect(result.with(cached: 4, killed: :key).to_h.slice(:cached, :killed)).to eq(cached: 4, killed: :key)
    end

    it "destructures as ok and note" do
      ok, note = result
      expect([ok, note]).to eq([true, "completed"])
    end
  end

  describe OpenLanes::Execution::Executor::Attempt do
    subject(:attempt) do
      described_class.new(agent: nil, subject: plan, root: "/r", profile: nil, trace: "t", handle: nil, sessions: nil)
    end

    let(:plan) { Struct.new(:feature).new(Struct.new(:ordinal).new("003.00")) }

    it "is built without a clock" do
      expect(attempt.clock).to be_nil
    end

    it "takes the clock once it has started" do
      expect(attempt.with(clock: :started).clock).to eq(:started)
    end

    it "names its plan as the log does" do
      expect(attempt.plan).to eq("003.00")
    end
  end

  describe OpenLanes::Execution::Executor::Request do
    it "takes the defaults Executor#call takes" do
      expect(described_class.new(root: "/r").to_h).to eq(root: "/r",
        control: nil,
        round: 1,
        successor: nil,
        partners: [],
        rebase: nil,
        resume: nil,
        brief: "")
    end
  end

  describe OpenLanes::Execution::Executor::Options do
    subject(:options) { described_class.new(root: ".", instructions: "  steer  ") }

    it "expands the root and strips the instructions" do
      expect([options.root, options.instructions]).to eq([File.expand_path("."), "steer"])
    end

    it "takes the defaults Executor#initialize takes" do
      expect(options.to_h.slice(:dry_run, :lean, :fresh_budget, :memory, :trace_dir, :usable, :timeout, :spawn))
        .to eq(dry_run: false,
          lean: true,
          fresh_budget: false,
          memory: true,
          trace_dir: OpenLanes::Execution::Executor::TRACE_DIR,
          usable: OpenLanes::Agents::Dealing::ANY,
          timeout: nil,
          spawn: nil)
    end

    it "gives every executor its own throttle" do
      expect(options.throttle).not_to equal(described_class.new(root: ".").throttle)
    end

    it "keeps what the caller gave" do
      expect(described_class.new(root: ".", dry_run: true, max_tokens: 9).to_h.slice(:dry_run, :max_tokens))
        .to eq(dry_run: true, max_tokens: 9)
    end
  end
end
