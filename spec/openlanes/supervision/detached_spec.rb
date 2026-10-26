# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::Detached do
  subject(:detached) { described_class.new(dir:, host: OpenLanes::Supervision::Host.new(spawner:, waiter:, clock:), answering:) }

  let(:root) { Dir.mktmpdir("detached") }
  let(:dir) { OpenLanes::Supervision::PidDir.new(File.join(root, "pids")) }
  let(:log) { File.join(root, "log", "openlanes-start.log") }
  let(:spawner) { OpenLanes::Spawner::Fake.new(pids: [4242]) }
  let(:clock) { OpenLanes::Clock::Fake.new }
  let(:answering) { ->(_port) { true } }
  let(:waiter) { ->(_pid) {} }
  let(:supervisor) { OpenLanes::Supervision::PidFile.new(role: "supervisor", pid: 4242, started: "x", root:, url: "http://127.0.0.1:11000") }
  let(:result) { detached.call(argv: %w[openlanes start], env: { "SECRET" => "s" }, log:, web: true) }

  after { FileUtils.rm_rf(root) }

  context "when the factory comes up" do
    before do
      dir.write(supervisor)
      result
    end

    it("returns its PID file") { expect(result.value!.pid).to eq(4242) }
    it("tells the child to leave the session") { expect(spawner.calls.first.env).to include("OPENLANES_DETACHED" => "1", "SECRET" => "s") }
    it("sends its output to the log") { expect(spawner.calls.first.options).to include(%i[out err] => [log, "a"]) }
  end

  context "when its page does not answer yet" do
    let(:answering) { ->(_port) { false } }

    before { dir.write(supervisor) }

    it("gives up after READY_WITHIN as 75") { expect(result.failure.status).to eq(75) }
    it("says it may still be starting") { expect(result.failure.message).to include("may still be starting") }
  end

  context "when it exits before it is up" do
    let(:waiter) { ->(_pid) { :gone } }

    before do
      FileUtils.mkdir_p(File.dirname(log))
      File.write(log, "boom\n")
    end

    it("refuses with 70") { expect(result.failure.status).to eq(70) }
    it("quotes the end of the log") { expect(result.failure.message).to end_with("boom\n") }
  end

  describe ".leave_session" do
    let(:env) { { "OPENLANES_DETACHED" => "1" } }

    before { allow(Process).to receive(:setsid) }

    context "with the variable set" do
      before { described_class.leave_session(env:) }

      it("starts a session of its own") { expect(Process).to have_received(:setsid) }
      it("removes the variable, so nothing it starts inherits it") { expect(env).to be_empty }
    end

    context "without the variable" do
      before { described_class.leave_session(env: {}) }

      it { expect(Process).not_to have_received(:setsid) }
    end

    context "when it already leads a session" do
      before { allow(Process).to receive(:setsid).and_raise(Errno::EPERM) }

      it { expect(described_class.leave_session(env:)).to be_nil }
    end
  end
end
