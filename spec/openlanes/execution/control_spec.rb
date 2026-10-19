# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Execution::Control do
  around do |example|
    Dir.mktmpdir("control") do |dir|
      @dir = dir
      example.run
    end
  ensure
    described_class.reset!
  end

  it "hands each invocation an empty file of its own" do
    path = described_class.register(@dir, "000.00-yoda-writer")

    expect(File.read(path)).to eq("")
    expect(File.basename(path)).to include("control-000.00-yoda-writer")
  end

  it "wrap_up! reaches every registered file" do
    one = described_class.register(@dir, "a")
    two = described_class.register(@dir, "b")
    described_class.wrap_up!

    expect(File.read(one).strip).to eq("WRAP_UP")
    expect(File.read(two).strip).to eq("WRAP_UP")
  end

  it "stop! asks agents to write out, without quitting the loop" do
    path = described_class.register(@dir, "a")
    described_class.stop!

    expect(File.read(path).strip).to eq("STOP")
    expect(described_class.quit?).to be(false)
  end

  it "quit! stops the agents and the loop both" do
    path = described_class.register(@dir, "a")
    described_class.quit!

    expect(File.read(path).strip).to eq("STOP")
    expect(described_class.quit?).to be(true)
  end

  describe "interrupt!" do
    let!(:path) { described_class.register(@dir, "a") }

    before { described_class.interrupt! }

    it "asks the agent for a resume note" do
      expect(File.read(path).strip).to eq("INTERRUPT")
    end

    it "quits the loop" do
      expect(described_class).to be_quit
    end

    it "remembers the interrupt" do
      expect(described_class).to be_interrupted
    end

    context "when the grace period has passed" do
      let(:later) { OpenLanes::UI.monotonic + described_class::GRACE + 1 }

      before { allow(OpenLanes::UI).to receive(:monotonic).and_return(later) }

      it "is overdue, on the same deadline as quit!" do
        expect(described_class).to be_overdue
      end
    end
  end

  describe "reset! after interrupt!" do
    before do
      described_class.interrupt!
      described_class.reset!
    end

    it "forgets the interrupt" do
      expect(described_class).not_to be_interrupted
    end
  end

  describe ".on_interrupt" do
    context "when SIGINT arrives twice" do
      let!(:outcome) { { raised: false } }

      before do
        described_class.on_interrupt do
          Process.kill("INT", Process.pid)
          sleep 0.05 until described_class.interrupted?
          begin
            Process.kill("INT", Process.pid)
            sleep 1
          rescue Interrupt
            outcome[:raised] = true
          end
        end
      end

      it "turns the first into interrupt! and the second into an Interrupt" do
        expect(outcome[:raised]).to be(true)
      end
    end

    context "with a handler already installed" do
      subject(:restored) { Signal.trap("INT", previous) }

      let!(:previous) { Signal.trap("INT") { nil } }

      before { described_class.on_interrupt { :ok } }

      it "puts the previous handler back" do
        expect(restored).to be_a(Proc)
      end
    end
  end

  # The deadline is what turns "please stop" into "stopped": inside the
  # grace period nothing is overdue, past it everything is.
  it "is overdue only once the grace period after quit! has passed" do
    described_class.quit!
    expect(described_class.overdue?).to be(false)

    allow(OpenLanes::UI).to receive(:monotonic)
      .and_return(OpenLanes::UI.monotonic + described_class::GRACE + 1)

    expect(described_class.overdue?).to be(true)
  end

  it "a released file is deleted and no longer written to" do
    path = described_class.register(@dir, "a")
    described_class.release(path)
    described_class.stop!

    expect(File.exist?(path)).to be(false)
  end

  it "reset! returns everything to rest" do
    path = described_class.register(@dir, "a")
    described_class.quit!
    described_class.reset!

    expect(described_class.quit?).to be(false)
    expect(described_class.overdue?).to be(false)
    expect(File.exist?(path)).to be(false)
  end

  # W32
  describe "pause! and resume!" do
    it "asks every agent to wait, then to carry on" do
      path = described_class.register(@dir, "001.00-luke-backend")
      described_class.pause!
      paused = [File.read(path), described_class.paused?]
      described_class.resume!

      expect([paused, [File.read(path), described_class.paused?]]).to eq([["PAUSE\n", true], ["RESUME\n", false]])
    end

    it "is lifted by quit!, which must stop the agents whatever their clocks say" do
      described_class.pause!
      described_class.quit!

      expect([described_class.paused?, described_class.quit?]).to eq([false, true])
    end
  end
end
