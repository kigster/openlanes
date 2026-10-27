# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::AgentSweep do
  subject(:sweep) { described_class.new(dir:, probe:, host: OpenLanes::Supervision::Host.new(signaller:, clock:)) }

  let(:root) { Dir.mktmpdir("agent-sweep") }
  let(:dir) { OpenLanes::Supervision::PidDir.new(File.join(root, "pids")) }
  let(:clock) { OpenLanes::Clock::Fake.new }
  let(:live) { [30, 31] }
  let(:stubborn) { [] }
  # Agents that end of their own accord once told INTERRUPT.
  let(:interruptible) { [] }
  let(:probe) { instance_double(OpenLanes::Supervision::Probe) }
  let(:signals) { [] }
  let(:signaller) do
    lambda do |signal, pid|
      signals << [signal, pid]
      case signal
      when "USR1" then live.delete(pid) if interruptible.include?(pid)
      when "TERM" then live.delete(pid) unless stubborn.include?(pid)
      else live.delete(pid)
      end
    end
  end

  def agent(pid, plan) = OpenLanes::Supervision::PidFile.new(role: "agent", pid:, started: "x", root:, plans: [plan], agent: "backend-coder", child: pid + 100)

  before do
    allow(probe).to receive(:verified?) { live.include?(it.pid) }
    files = [agent(30, "005.00"), agent(31, "006.00"), agent(32, "007.00"), nil]
    allow(dir).to receive(:entries).and_return(files.map { OpenLanes::Supervision::PidDir::Entry.new(path: "x", file: it) })
  end

  after { FileUtils.rm_rf(root) }

  describe "#interrupt" do
    let!(:told) { sweep.interrupt }

    it("sends USR1 to every live agent at once") { expect(signals).to eq([["USR1", 30], ["USR1", 31]]) }
    it("names them") { expect(told.map(&:pid)).to eq([30, 31]) }
  end

  context "with agents that stop when told" do
    let!(:stopped) { sweep.call }

    it("TERMs every live agent at once") { expect(signals).to eq([["TERM", 30], ["TERM", 31]]) }
    it("names the agents it stopped") { expect(stopped).to eq(agent(30, "005.00") => :stopped, agent(31, "006.00") => :stopped) }
    it("leaves one already gone alone") { expect(signals.map(&:last)).not_to include(32) }
  end

  context "with agents that end within the grace once interrupted" do
    let(:interruptible) { [30, 31] }
    let!(:stopped) do
      sweep.interrupt
      sweep.call(grace: 60)
    end

    it("never TERMs them") { expect(signals.map(&:first)).to eq(%w[USR1 USR1]) }
    it("still names them stopped") { expect(stopped.values).to eq(%i[stopped stopped]) }
    it("waits no longer than they take") { expect(clock.monotonic).to be < 1 }
  end

  context "with an agent that outlasts the grace" do
    let(:interruptible) { [30] }

    before do
      sweep.interrupt
      sweep.call(grace: 60)
    end

    it("TERMs it once the grace is out") { expect(signals.last).to eq(["TERM", 31]) }
    it("after the whole grace") { expect(clock.monotonic).to be >= 60 }
  end

  context "with an agent that outlives its stop" do
    let(:stubborn) { [31] }
    let!(:stopped) { sweep.call }

    it("KILLs its CLI's group, then it") { expect(signals.last(2)).to eq([["KILL", -131], ["KILL", 31]]) }
    it("after its whole stop") { expect(clock.monotonic).to be >= described_class::WITHIN }
    it("names it killed") { expect(stopped[agent(31, "006.00")]).to eq(:killed) }
  end

  context "with an agent whose CLI is not named" do
    let(:stubborn) { [30] }
    let(:live) { [30] }

    before do
      allow(dir).to receive(:entries).and_return([OpenLanes::Supervision::PidDir::Entry.new(path: "x",
        file: OpenLanes::Supervision::PidFile.new(role: "agent", pid: 30, started: "x", root:))])
      sweep.call
    end

    it("KILLs the agent supervisor alone") { expect(signals.last).to eq(["KILL", 30]) }
  end
end
