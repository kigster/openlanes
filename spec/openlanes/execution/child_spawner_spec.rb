# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Child do
  context "with a fake spawner" do
    it "starts nothing and keeps the pid the spawner handed back" do
      spawner = OpenLanes::Spawner::Fake.new(pids: [4242])
      child = described_class.spawn(%w[claude -p hello], chdir: "/tmp", env: { "A" => "1" }, spawner:)
      described_class.forget(child)
      call = spawner.calls.first
      aggregate_failures do
        expect(child.pid).to eq(4242)
        expect(call.argv).to eq(%w[claude -p hello])
        expect(call.env).to include("A" => "1")
        expect(call.options).to include(chdir: "/tmp", pgroup: true, unsetenv_others: true)
      end
    end
  end

  # The rescue branches are reached only when a real process group happens to
  # empty at the right moment, so a suite that covers them by timing covers
  # them on some runs and not others: CI once saw this file at 94.52% while a
  # laptop saw 95.89%. Here every errno is raised on purpose, against a pid
  # that was never started.
  context "when the operating system refuses" do
    subject(:child) { described_class.new(pid: 4242, reader:) }

    let(:pipe) { IO.pipe }
    let(:reader) { pipe.first }

    before { pipe.last.close }
    after { reader.close unless reader.closed? }

    it "keeps no status when the pid was already reaped elsewhere" do
      allow(Process).to receive(:wait2).and_raise(Errno::ECHILD)
      expect(child.wait).to be_nil
    end

    it "stops signalling a group once it has answered ESRCH" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)
      2.times { child.kill("TERM") }
      expect(Process).to have_received(:kill).once
    end

    it "leaves alone a group it may not signal" do
      allow(Process).to receive(:kill).and_raise(Errno::EPERM)
      expect { child.kill }.not_to raise_error
    end

    it "reports a pid that is gone as not alive" do
      allow(Process).to receive(:kill).with(0, 4242).and_raise(Errno::ESRCH)
      expect(child).not_to be_alive
    end

    it "terminates once, closing the pipe, when every signal is refused" do
      allow(Process).to receive(:kill).and_raise(Errno::EPERM)
      2.times { child.terminate(grace: 0, drain: 0) }
      aggregate_failures do
        expect(reader).to be_closed
        expect(Process).to have_received(:kill).with("TERM", -4242).once
      end
    end

    it "counts an emptied group as finished once the leader is reaped" do
      allow(Process).to receive_messages(wait2: [4242, instance_double(Process::Status)])
      allow(Process).to receive(:kill).with(0, -4242).and_raise(Errno::ESRCH)
      child.wait
      aggregate_failures do
        expect(child).to be_finished
        expect(child).to be_finished
        expect(Process).to have_received(:kill).with(0, -4242).once
      end
    end
  end
end
