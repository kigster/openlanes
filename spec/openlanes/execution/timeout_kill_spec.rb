# frozen_string_literal: true

# `openlanes start --timeout 600` once ran for good: the agent's Bash tool ran
# `ls`, a shell alias turned it into `eza`, and `eza` hung. The clock fired,
# STOP went unread, and the SIGKILL that followed reached `claude` alone. The
# shell under it kept the write end of the agent's stdout open, so the reader
# never saw end of file and the attempt never ended.
#
# These examples spawn real processes that do the same: a child that ignores
# STOP and leaves a grandchild sleeping with stdout inherited.
RSpec.describe "Ending an agent that will not end" do
  # A grandchild that sleeps for good with the child's stdout, its pid left in
  # +pidfile+ so the example can see it go and clean it up if it does not.
  def stubborn(pidfile, ignore_term: false)
    trap = ignore_term ? "trap '' TERM; " : ""
    ["sh", "-c", "#{trap}sleep 30 & echo $! > \"$0\"; wait", pidfile]
  end

  # The same grandchild in a session of its own, as `setsid` or a daemonising
  # double fork leaves one: no signal sent to the group reaches it.
  def escaped(pidfile)
    script = "Process.setsid; File.write(ARGV[0], Process.pid.to_s); sleep 30"
    ["sh", "-c", "#{RbConfig.ruby.shellescape} -e #{script.shellescape} \"$0\" & wait", pidfile]
  end

  # A grandchild that ignores TERM and does not hold the pipe, under a leader
  # TERM does end: the reader reaches end of file and the leader is reaped
  # while the group still has a member. With +leader_waits+ false the leader
  # exits at once of its own accord.
  def detached(pidfile, leader_waits: true)
    wait = leader_waits ? "; wait" : ""
    ["sh", "-c", "(trap '' TERM; exec sleep 30) >/dev/null 2>&1 & echo $! > \"$0\"#{wait}", pidfile]
  end

  def grandchild = Integer(File.read(pidfile))

  def gone?(pid)
    Process.kill(0, pid)
    false
  rescue Errno::ESRCH
    true
  end

  # Reparented to init once its parent dies, the grandchild is reaped there,
  # not here; this waits for that, up to a second.
  def gone_soon?(pid)
    deadline = OpenLanes::UI.monotonic + 1
    sleep(0.02) until gone?(pid) || OpenLanes::UI.monotonic > deadline
    gone?(pid)
  end

  let(:dir) { Dir.mktmpdir("timeout-kill") }
  let(:pidfile) { File.join(dir, "grandchild.pid") }

  after do
    pid = File.exist?(pidfile) && grandchild
    Process.kill("KILL", pid) if pid && !gone?(pid)
    FileUtils.rm_rf(dir)
  end

  describe OpenLanes::Execution::Executor, :tree do
    subject(:executor) { described_class.new(root:, spawn:, timeout: 0, trace_dir: File.join(dir, "traces")) }

    let(:root) { File.dirname(plans_root) }
    let(:agent) { OpenLanes::Agents.find("backend-coder") }
    # The argv is built before the lambda exists: a let read from the call's
    # thread would wait on the memoization lock the main thread holds. The
    # child is handed back only once the grandchild is up, so the clock,
    # started after it, cannot fire first.
    let(:argv) { stubborn(pidfile) }
    let(:spawn) do
      path = pidfile
      argv = self.argv
      lambda { |_argv, chdir:, env:, **|
        OpenLanes::Execution::Child.spawn(argv, chdir:, env:).tap { sleep(0.01) until File.size?(path) }
      }
    end
    let(:plan) do
      plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
      OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
    end
    # The real call, on a thread, so a hang fails the example instead of the
    # suite. Its arguments are resolved here, on the main thread.
    let(:attempt) do
      call = [executor, agent, plan]
      Thread.new { call.first.call(*call.drop(1)) }.tap { it.report_on_exception = false }
    end
    let(:result) { attempt.join(2)&.value }

    # The budget is zero and so is the grace after STOP, so the clock's first
    # tick is its last.
    before do
      stub_const("OpenLanes::Execution::Clock::GRACE", 0)
      stub_const("OpenLanes::Execution::Child::TERM_GRACE", 0.2)
    end

    after { OpenLanes::Execution::Control.reset! }

    it "ends the attempt once the clock runs out" do
      expect(result).not_to be_nil
    end

    it "reports it as a timeout" do
      expect(result).to have_attributes(ok: false, killed: :timeout, note: a_string_including("timed out"))
    end

    it "takes the grandchild down with the agent" do
      result
      expect(gone_soon?(grandchild)).to be(true)
    end

    # The leader dies on TERM, the reader sees end of file, and the executor
    # stops the clock while its thread is still inside the TERM grace.
    context "when the leader is reaped before the KILL" do
      let(:argv) { detached(pidfile) }

      it "still KILLs the TERM-ignoring grandchild" do
        result
        expect(gone_soon?(grandchild)).to be(true)
      end
    end
  end

  describe OpenLanes::Execution::Child do
    let(:child) { described_class.spawn(argv) }
    let(:argv) { stubborn(pidfile, ignore_term:) }
    let(:ignore_term) { false }
    let(:reader) { Thread.new { child.each_chunk { nil } } }

    # Up once the grandchild has written its pid, so a signal cannot beat it.
    before do
      child
      sleep(0.01) until File.size?(pidfile)
    end

    it "leads a process group of its own" do
      expect(Process.getpgid(child.pid)).to eq(child.pid)
    end

    it "lets the reader finish once the group is terminated" do
      reader
      child.terminate(grace: 0.2)
      expect(reader.join(2)).not_to be_nil
    end

    it "reaps the agent after terminating it" do
      reader
      child.terminate(grace: 0.2)
      reader.join(2)
      expect(child.wait).not_to be_success
    end

    it "is forgotten once reaped with its group gone" do
      reader
      child.terminate(grace: 0.2)
      reader.join(2)
      gone_soon?(grandchild)
      child.wait
      expect(described_class.live).not_to include(child)
    end

    context "with a grandchild that ignores TERM" do
      let(:ignore_term) { true }

      it "KILLs what TERM left behind" do
        reader
        child.terminate(grace: 0.2)
        expect(gone_soon?(grandchild)).to be(true)
      end
    end

    # Closing the pipe is what still ends the reader when a process out of
    # reach of the group's signals holds it.
    context "when something outside the group holds the pipe" do
      let(:argv) { escaped(pidfile) }

      it "closes the pipe under the reader" do
        reader
        child.terminate(grace: 0, drain: 0.1)
        expect(reader.join(2)).not_to be_nil
      end
    end

    it "terminates once, however often it is asked" do
      allow(child).to receive(:kill).and_call_original
      reader
      2.times { child.terminate(grace: 0.2) }
      expect(child).to have_received(:kill).with("TERM").once
    end

    it "KILLs every live group when the harness exits" do
      described_class.terminate_all
      expect(gone_soon?(grandchild)).to be(true)
    end

    context "with a TERM-ignoring grandchild that does not hold the pipe" do
      let(:argv) { detached(pidfile) }
      let(:stopper) { Thread.new { child.terminate(grace: 0.5) } }

      # The reader finishes and the leader is reaped mid-grace, as the
      # executor does on its own thread.
      it "KILLs the group even when the leader is reaped mid-grace" do
        reader
        stopper
        reader.join(2)
        child.wait
        stopper.join(2)
        expect(gone_soon?(grandchild)).to be(true)
      end
    end

    context "with a leader that exits and leaves a member behind" do
      let(:argv) { detached(pidfile, leader_waits: false) }

      it "KILLs the rest of the group when the harness exits" do
        reader.join(2)
        child.wait
        described_class.terminate_all
        expect(gone_soon?(grandchild)).to be(true)
      end
    end
  end
end
