# frozen_string_literal: true

RSpec.describe OpenLanes::Spawner do
  describe OpenLanes::Spawner::System do
    it "starts a real process and returns its pid" do
      pid = described_class.spawn({ "X" => "1" }, "ruby", "-e", "exit(ENV['X'] == '1' ? 0 : 3)", in: File::NULL)
      _, status = Process.wait2(pid)
      expect(status.exitstatus).to eq(0)
    end
  end

  describe OpenLanes::Spawner::Fake do
    it "hands out the scripted pids, then counts on" do
      spawner = described_class.new(pids: [41], first_pid: 100)
      expect([spawner.spawn({}, "a"), spawner.spawn({}, "b")]).to eq([41, 101])
    end

    it "records what it was asked to start" do
      spawner = described_class.new
      spawner.spawn({ "K" => "v" }, "git", "fetch", pgroup: true)
      expect(spawner.calls).to eq([described_class::Call.new(env: { "K" => "v" },
        argv: %w[git fetch],
        options: { pgroup: true })])
    end

    it "starts nothing" do
      allow(Process).to receive(:spawn)
      described_class.new.spawn({}, "rm", "-rf", "/")
      expect(Process).not_to have_received(:spawn)
    end
  end
end
