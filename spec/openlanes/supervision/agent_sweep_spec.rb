# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::AgentSweep do
  subject(:sweep) { described_class.new(dir:, probe:, host: OpenLanes::Supervision::Host.new(signaller:, clock:)) }

  let(:root) { Dir.mktmpdir("agent-sweep") }
  let(:dir) { OpenLanes::Supervision::PidDir.new(File.join(root, "pids")) }
  let(:clock) { OpenLanes::Clock::Fake.new }
  let(:live) { [30, 31] }
  let(:stubborn) { [] }
  let(:probe) { instance_double(OpenLanes::Supervision::Probe) }
  let(:signals) { [] }
  let(:signaller) do
    lambda do |signal, pid|
      signals << [signal, pid]
      live.delete(pid) unless signal == "TERM" && stubborn.include?(pid)
    end
  end

  def agent(pid, plan) = OpenLanes::Supervision::PidFile.new(role: "agent", pid:, started: "x", root:, plans: [plan], agent: "backend-coder", child: pid + 100)

  before do
    allow(probe).to receive(:verified?) { live.include?(it.pid) }
    files = [agent(30, "005.00"), agent(31, "006.00"), agent(32, "007.00"), nil]
    allow(dir).to receive(:entries).and_return(files.map { OpenLanes::Supervision::PidDir::Entry.new(path: "x", file: it) })
  end

  after { FileUtils.rm_rf(root) }

  context "with agents that stop when told" do
    let!(:stopped) { sweep.call }

    it("TERMs every live agent at once") { expect(signals).to eq([["TERM", 30], ["TERM", 31]]) }
    it("names the agents it stopped") { expect(stopped.map(&:pid)).to eq([30, 31]) }
    it("leaves one already gone alone") { expect(signals.map(&:last)).not_to include(32) }
  end

  context "with an agent that outlives its stop" do
    let(:stubborn) { [31] }

    before { sweep.call }

    it("KILLs its CLI's group, then it") { expect(signals.last(2)).to eq([["KILL", -131], ["KILL", 31]]) }
    it("after its whole stop") { expect(clock.monotonic).to be >= described_class::WITHIN }
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
