# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::Supervisor do
  subject(:supervisor) do
    described_class.new(programs:, registration:, lifeline:, host: OpenLanes::Supervision::Host.new(spawner:, waiter:, signaller:, clock:))
  end

  let(:root) { Dir.mktmpdir("supervisor") }
  let(:dir) { OpenLanes::Supervision::PidDir.new(File.join(root, "pids")) }
  let(:titles) { [] }
  let(:registration) do
    OpenLanes::Supervision::Registration.new(draft: OpenLanes::Supervision::PidFile.new(role: "supervisor", pid: Process.pid, started: nil, root:),
      dir:,
      probe: instance_double(OpenLanes::Supervision::Probe, started: "x", verified?: false),
      title: OpenLanes::Supervision::Title.new(role: "supervisor", root:, setter: ->(text) { titles << text }))
  end
  let(:lifeline) { instance_double(OpenLanes::Supervision::Lifeline, env: { "OPENLANES_LIFELINE" => "9" }, options: { 9 => 9 }, cut: nil) }
  let(:spawner) { OpenLanes::Spawner::Fake.new(pids: (101..120).to_a) }
  let(:clock) { OpenLanes::Clock::Fake.new }
  let(:programs) do
    [OpenLanes::Supervision::Program.new(role: "engine", argv: %w[engine], essential: true),
     OpenLanes::Supervision::Program.new(role: "web", argv: %w[web], env: { "OPENLANES_REDIS_URL" => "redis://x" })]
  end
  let(:on_tick) { nil }

  # pid => [status, whether it crashed, leaving its PID file], reported once
  let(:ends) { {} }
  let(:waiter) do
    lambda do |pid|
      status, crashed = ends.delete(pid)
      dir.write(OpenLanes::Supervision::PidFile.new(role: role_of(pid), pid:, started: "x", root:)) if crashed
      status
    end
  end
  let(:signals) { [] }
  let(:signaller) do
    # The supervisor signals each child's process group.
    lambda do |signal, group|
      pid = -group
      signals << [signal, pid]
      ends[pid] = [exited(0), false] unless signal == "TERM" && stubborn.include?(pid)
    end
  end
  let(:stubborn) { [] }

  def exited(code) = instance_double(Process::Status, exitstatus: code, signaled?: false)
  def killed = instance_double(Process::Status, exitstatus: nil, signaled?: true, termsig: 9)
  def role_of(pid) = spawner.calls.fetch(pid - 101).argv.first
  def spawned = spawner.calls.map { it.argv.first }

  before { registration.claim }

  after { FileUtils.rm_rf(root) }

  context "when the engine ends of its own accord" do
    let(:on_tick) { ->(_) { ends[101] = [exited(3), false] } }

    let!(:status) { supervisor.call(&on_tick) }

    it("ends the factory with the engine's status") { expect(status).to eq(3) }
    it("stops the web") { expect(signals).to eq([["TERM", 102]]) }
    it("starts each child once") { expect(spawned).to eq(%w[engine web]) }
  end

  describe "how it starts a child" do
    let(:on_tick) { lambda(&:stop!) }

    before { supervisor.call(&on_tick) }

    it("in a process group of its own, stdin closed") { expect(spawner.calls.first.options).to include(pgroup: true, in: File::NULL, 9 => 9) }
    it("with the lifeline in its environment") { expect(spawner.calls.last.env).to eq("OPENLANES_REDIS_URL" => "redis://x", "OPENLANES_LIFELINE" => "9") }
  end

  context "when a child crashes" do
    let(:on_tick) do
      lambda do |s|
        ends[102] = [killed, true] if spawner.calls.size == 2 && !ends.key?(102) && s.slots.last.running?
        s.stop! if spawner.calls.size == 3
      end
    end

    before { supervisor.call(&on_tick) }

    it("starts it again") { expect(spawned).to eq(%w[engine web web]) }
    it("after the backoff") { expect(clock.monotonic).to be >= 1 }
    it("counts the restart") { expect(supervisor.slots.last.restarts).to eq(1) }
  end

  context "when a child crashes three times inside five minutes" do
    let(:on_tick) do
      lambda do |s|
        web = s.slots.last
        ends[web.pid] = [killed, true] if web.running? && !ends.key?(web.pid)
        s.stop! if web.given_up
      end
    end

    before { supervisor.call(&on_tick) }

    it("gives up on it") { expect(spawned).to eq(%w[engine web web web]) }
    it("says why in the PID file") { expect(registration.file.failed).to eq("web" => "3 crashes in 5m") }
    it("keeps the engine up until told to stop") { expect(signals).to eq([["TERM", 101]]) }
  end

  context "when the web ends on purpose" do
    let(:on_tick) do
      lambda do |s|
        ends[102] = [exited(69), false] if s.slots.last.running?
        s.stop! if s.slots.last.given_up
      end
    end

    before { supervisor.call(&on_tick) }

    it("leaves it stopped") { expect(spawned).to eq(%w[engine web]) }
    it("says why") { expect(registration.file.failed).to eq("web" => "exited 69") }
  end

  context "when every child is given up on" do
    let(:programs) { [OpenLanes::Supervision::Program.new(role: "web", argv: %w[web])] }
    let(:on_tick) { ->(_) { ends[101] ||= [exited(69), false] } }

    it("ends with 1") { expect(supervisor.call(&on_tick)).to eq(1) }
  end

  context "when told to stop" do
    let(:on_tick) { lambda(&:stop!) }

    let!(:status) { supervisor.call(&on_tick) }

    it("TERMs every child") { expect(signals).to eq([["TERM", 101], ["TERM", 102]]) }
    it("ends with 0") { expect(status).to eq(0) }
    it("cuts the lifeline") { expect(lifeline).to have_received(:cut) }
  end

  context "when a child outlives TERM" do
    let(:stubborn) { [101] }
    let(:on_tick) { lambda(&:stop!) }

    before { supervisor.call(&on_tick) }

    it("KILLs it after the grace") { expect(signals).to eq([["TERM", 101], ["TERM", 102], ["KILL", 101]]) }
    it("waited the grace out") { expect(clock.monotonic).to be >= described_class::GRACE }
  end

  context "when told to stop twice" do
    let(:stubborn) { [101] }
    let(:on_tick) { ->(s) { 2.times { s.stop! } } }

    before { supervisor.call(&on_tick) }

    it("KILLs at once") { expect(clock.monotonic).to be < 1 }
  end

  describe "its title" do
    let(:on_tick) { lambda(&:stop!) }

    before { supervisor.call(&on_tick) }

    it { expect(titles.last).to end_with("] up 0s, 0 restarts") }
  end

  describe "its title with a child down" do
    let(:on_tick) do
      lambda do |s|
        ends[102] = [exited(69), false] if s.slots.last.running?
        clock.advance(described_class::TITLE_EVERY)
        s.stop! if titles.last.end_with?("down")
      end
    end

    before { supervisor.call(&on_tick) }

    it { expect(titles.last).to match(/\] up \d+s, 0 restarts, web down\z/) }
  end
end
