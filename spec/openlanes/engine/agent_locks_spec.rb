# frozen_string_literal: true

# W31: the plans an agent outside openlanes holds in alock, and the engine's
# own locks in the same register. `alock` never runs: a command double
# answers for it, the way it answers on the command line.
RSpec.describe OpenLanes::Engine::AgentLocks do
  subject(:locks) { described_class.new(root:, id: "openlanes@test", own: %w[backend-coder], command:, clock: -> { time.first }) }

  let(:root) { Dir.mktmpdir("agent-locks") }
  let(:plans) { File.join(root, ".plans") }
  let(:folder) { File.join(plans, "003.00━━🟡━━❯tax-rule-dsl") }
  let(:checkout) { File.join(root, "..", "worktrees", "003.00-tax-rule-dsl") }
  let(:time) { [100.0] }
  let(:command) { instance_double(TTY::Command) }
  let(:listed) { [] }

  def lock(scope, agent: "claude-1", tree: root, status: "active", intent: "refactoring")
    { "agent_id" => agent, "scope" => scope, "tree" => tree, "status" => status, "intent" => intent }
  end

  def result(status, out: "", err: "") = instance_double(TTY::Command::Result, exit_status: status, success?: status.zero?, out:, err:)

  before do
    FileUtils.mkdir_p(folder)
    allow(command).to receive(:run).with("alock", "list", "--json", "--dir", File.realpath(root)) { result(0, out: JSON.generate(listed)) }
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

    it "ignores other plans, other checkouts, the engine's own locks and locks no longer active" do
      listed.push(lock(".plans/004.00━━🟡━━❯other/**"),
        lock("**", tree: File.join(root, "..", "elsewhere")),
        lock(".plans/003.00━━🟡━━❯tax-rule-dsl/**", agent: "openlanes@test"),
        lock("**", status: "interrupted"))

      expect(locks.held_elsewhere(folder, checkout:)).to be_nil
    end

    it "asks alock once per #{described_class::FRESH} seconds" do
      3.times { locks.held_elsewhere(folder) }
      time[0] += described_class::FRESH
      locks.held_elsewhere(folder)

      expect(command).to have_received(:run).twice
    end

    it "says a failing listing once, not on every pass, and again after it recovers" do
      failure = TTY::Command::ExitError.new("alock list --json", result(1, err: "can't find executable alock"))
      answers = [:fail, :fail, :ok, :fail]
      allow(command).to receive(:run) do
        answers.shift == :fail ? raise(failure) : result(0, out: "[]")
      end
      allow(OpenLanes::UI).to receive(:log)
      4.times do
        locks.held_elsewhere(folder)
        time[0] += described_class::FRESH
      end

      expect(OpenLanes::UI).to have_received(:log)
        .with("alock list failed, plans unchecked until it works: stderr: can't find executable alock", level: :warn).twice
    end

    it "checks nothing this pass when alock answers nonsense, and says so" do
      allow(command).to receive(:run).and_return(result(0, out: "not json"))
      allow(OpenLanes::UI).to receive(:log)

      aggregate_failures do
        expect(locks.held_elsewhere(folder)).to be_nil
        expect(OpenLanes::UI).to have_received(:log).with(/alock list failed/, level: :warn)
      end
    end
  end

  describe "#acquire and #release" do
    let(:argv) { ["--dir", plans, { env: { "AGENT_ID" => "openlanes@test" } }] }

    it "claims the folder and everything in it, as the engine" do
      allow(command).to receive(:run!).and_return(result(0))

      aggregate_failures do
        expect(locks.acquire(folder, "openlanes: backend-coder on 003.00")).to be(true)
        expect(command).to have_received(:run!)
          .with("alock", "acquire", "003.00━━🟡━━❯tax-rule-dsl/**", "openlanes: backend-coder on 003.00", *argv)
      end
    end

    it "is refused when somebody else holds it" do
      allow(command).to receive(:run!).and_return(result(1, out: "REFUSED, do not write here"))

      expect(locks.acquire(folder, "x")).to be(false)
    end

    it "counts alock failing as a refusal, and says why" do
      allow(command).to receive(:run!).and_return(result(2, err: "empty scope"))
      allow(OpenLanes::UI).to receive(:log)

      aggregate_failures do
        expect(locks.acquire(folder, "x")).to be(false)
        expect(OpenLanes::UI).to have_received(:log)
          .with("alock acquire 003.00━━🟡━━❯tax-rule-dsl/** failed: empty scope", level: :warn)
      end
    end

    it "names the scope a failed release leaves held" do
      allow(command).to receive(:run!).and_return(result(2, err: "store gone"))
      allow(OpenLanes::UI).to receive(:log)
      locks.release(folder)

      expect(OpenLanes::UI).to have_received(:log).with(
        "alock release 003.00━━🟡━━❯tax-rule-dsl/** failed: store gone; 003.00━━🟡━━❯tax-rule-dsl/** stays held until the engine exits",
        level: :warn
      )
    end

    it "gives the folder back" do
      allow(command).to receive(:run!).and_return(result(0))
      locks.release(folder)

      expect(command).to have_received(:run!).with("alock", "release", "003.00━━🟡━━❯tax-rule-dsl/**", *argv)
    end

    it "asks again after a lock it took, rather than trusting the old answer" do
      allow(command).to receive(:run!).and_return(result(0))
      locks.held_elsewhere(folder)
      locks.acquire(folder, "x")
      locks.held_elsewhere(folder)

      expect(command).to have_received(:run).twice
    end
  end

  context "without alock installed" do
    before do
      allow(command).to receive(:run).and_raise(Errno::ENOENT, "alock")
      allow(command).to receive(:run!).and_raise(Errno::ENOENT, "alock")
      allow(OpenLanes::UI).to receive(:log)
    end

    it "lets every plan through, and says so once" do
      aggregate_failures do
        expect(locks.held_elsewhere(folder)).to be_nil
        expect(locks.acquire(folder, "x")).to be(true)
        expect(locks.held_elsewhere(folder)).to be_nil
        expect(OpenLanes::UI).to have_received(:log).with(/alock is not installed/, level: :warn).once
      end
    end
  end
end
