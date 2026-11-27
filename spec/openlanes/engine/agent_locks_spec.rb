# frozen_string_literal: true

# W31: the plans an agent outside openlanes holds in alock, and the engine's
# own locks in the same register. No register is asked: an adapter double
# answers for it, as Locking::Distributed would.
RSpec.describe OpenLanes::Engine::AgentLocks do
  subject(:locks) { described_class.new(root:, id: "openlanes@test", own: %w[backend-coder], adapter:, clock: -> { time.first }) }

  let(:root) { Dir.mktmpdir("agent-locks") }
  let(:plans) { File.join(root, ".plans") }
  let(:folder) { File.join(plans, "003.00━━🟡━━❯tax-rule-dsl") }
  let(:checkout) { File.join(root, "..", "worktrees", "003.00-tax-rule-dsl") }
  let(:time) { [100.0] }
  let(:adapter) { instance_double(OpenLanes::Locking::Distributed) }
  let(:listed) { [] }

  def lock(scope, agent: "claude-1", tree: root, intent: "refactoring") = OpenLanes::Locking::Lock.new(agent:, scope:, tree:, intent:)

  def outcome(status, message = "") = OpenLanes::Locking::Outcome.new(status:, message:)

  before do
    FileUtils.mkdir_p(folder)
    allow(adapter).to receive(:list).with(File.realpath(root)) { listed.dup }
  end

  after { FileUtils.rm_rf(root) }

  # Asked before a merged plan's checkout is removed: any lock at all in it
  # means somebody is in there, the engine's own agents included.
  describe "#held_in" do
    before { FileUtils.mkdir_p(checkout) }

    it "names whoever holds a lock in the checkout, one of the engine's agents included" do
      listed << lock("lib/a.rb", agent: "backend-coder", tree: checkout)

      expect(locks.held_in(checkout).to_s).to eq("backend-coder (refactoring)")
    end

    it "ignores locks taken in any other tree" do
      listed << lock("lib/a.rb")

      expect(locks.held_in(checkout)).to be_nil
    end
  end

  describe "#held_elsewhere" do
    it "names somebody else's lock on the plan's folder" do
      listed << lock(".plans/003.00━━🟡━━❯tax-rule-dsl/spec.md")

      expect(locks.held_elsewhere(folder).to_s).to eq("claude-1 (refactoring)")
    end

    it "counts a lock on everything above the folder, the whole tree included" do
      listed << lock("**")

      expect(locks.held_elsewhere(folder)).not_to be_nil
    end

    it "counts any lock inside the plan's worktree" do
      FileUtils.mkdir_p(checkout)
      listed << lock("lib/a.rb", tree: checkout)

      expect(locks.held_elsewhere(folder, checkout:)).not_to be_nil
    end

    it "ignores the engine's own agents and their sub-agents, in the worktree or on the folder" do
      FileUtils.mkdir_p(checkout)
      listed.push(lock("lib/a.rb", agent: "backend-coder", tree: checkout),
        lock("lib/b.rb", agent: "backend-coder-schema", tree: checkout),
        lock(".plans/003.00━━🟡━━❯tax-rule-dsl/plan.md", agent: "backend-coder"))

      expect(locks.held_elsewhere(folder, checkout:)).to be_nil
    end

    it "still counts an agent whose name only starts like one of the engine's" do
      FileUtils.mkdir_p(checkout)
      listed << lock("lib/a.rb", agent: "backend-coderish", tree: checkout)

      expect(locks.held_elsewhere(folder, checkout:)).not_to be_nil
    end

    it "ignores other plans, other checkouts and the engine's own locks" do
      listed.push(lock(".plans/004.00━━🟡━━❯other/**"),
        lock("**", tree: File.join(root, "..", "elsewhere")),
        lock(".plans/003.00━━🟡━━❯tax-rule-dsl/**", agent: "openlanes@test"))

      expect(locks.held_elsewhere(folder, checkout:)).to be_nil
    end

    it "asks the register once per #{described_class::FRESH} seconds" do
      3.times { locks.held_elsewhere(folder) }
      time[0] += described_class::FRESH
      locks.held_elsewhere(folder)

      expect(adapter).to have_received(:list).twice
    end

    it "says a failing listing once, not on every pass, and again after it recovers" do
      answers = [:fail, :fail, :ok, :fail]
      allow(adapter).to receive(:list) do
        answers.shift == :fail ? raise(OpenLanes::Locking::Unreadable, "Redis did not answer") : []
      end
      allow(OpenLanes::UI).to receive(:log)
      4.times do
        locks.held_elsewhere(folder)
        time[0] += described_class::FRESH
      end

      expect(OpenLanes::UI).to have_received(:log)
        .with("alock list failed, plans unchecked until it works: Redis did not answer", level: :warn).twice
    end
  end

  describe "#acquire and #release" do
    it "claims the folder and everything in it, as the engine" do
      allow(adapter).to receive(:acquire).and_return(outcome(:done))

      aggregate_failures do
        expect(locks.acquire(folder, "openlanes: backend-coder on 003.00")).to be(true)
        expect(adapter).to have_received(:acquire)
          .with("003.00━━🟡━━❯tax-rule-dsl/**", "openlanes: backend-coder on 003.00", dir: plans, as: "openlanes@test")
      end
    end

    it "is refused when somebody else holds it" do
      allow(adapter).to receive(:acquire).and_return(outcome(:refused, "REFUSED, do not write here"))

      expect(locks.acquire(folder, "x")).to be(false)
    end

    it "counts the register failing as a refusal, and says why" do
      allow(adapter).to receive(:acquire).and_return(outcome(:failed, "Redis did not answer"))
      allow(OpenLanes::UI).to receive(:log)

      aggregate_failures do
        expect(locks.acquire(folder, "x")).to be(false)
        expect(OpenLanes::UI).to have_received(:log)
          .with("alock acquire 003.00━━🟡━━❯tax-rule-dsl/** failed: Redis did not answer", level: :warn)
      end
    end

    it "names the scope a failed release leaves held" do
      allow(adapter).to receive(:release).and_return(outcome(:failed, "store gone"))
      allow(OpenLanes::UI).to receive(:log)
      locks.release(folder)

      expect(OpenLanes::UI).to have_received(:log).with(
        "alock release 003.00━━🟡━━❯tax-rule-dsl/** failed: store gone; 003.00━━🟡━━❯tax-rule-dsl/** stays held until the engine exits",
        level: :warn
      )
    end

    it "gives the folder back" do
      allow(adapter).to receive(:release).and_return(outcome(:done))
      locks.release(folder)

      expect(adapter).to have_received(:release).with("003.00━━🟡━━❯tax-rule-dsl/**", dir: plans, as: "openlanes@test")
    end

    it "asks again after a lock it took, rather than trusting the old answer" do
      allow(adapter).to receive(:acquire).and_return(outcome(:done))
      locks.held_elsewhere(folder)
      locks.acquire(folder, "x")
      locks.held_elsewhere(folder)

      expect(adapter).to have_received(:list).twice
    end
  end
end
