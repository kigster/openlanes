# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::Probe do
  subject(:probe) { described_class.new(query: ->(pid) { table.fetch(pid, "") }) }

  let(:table) { { 42 => "Mon Oct  5 01:21:45 2026     openlanes-engine [myproj] 1 of 4 agents busy  \n" } }
  let(:file) { OpenLanes::Supervision::PidFile.new(role: "engine", pid: 42, started: "Mon Oct  5 01:21:45 2026", root: "/work/myproj") }

  describe "#seen" do
    it { expect(probe.seen(42)).to eq(described_class::Seen.new(started: "Mon Oct  5 01:21:45 2026", command: "openlanes-engine [myproj] 1 of 4 agents busy")) }

    it("sees nothing of a pid that is gone") { expect(probe.seen(7)).to be_nil }
  end

  describe "#verified?" do
    it("trusts the process the file names") { expect(probe.verified?(file)).to be(true) }

    it("rejects a reused pid that started at another time") { expect(probe.verified?(file.with(started: "Sun Oct  4 01:21:45 2026"))).to be(false) }

    it("rejects a process with another title") { expect(probe.verified?(file.with(root: "/work/other"))).to be(false) }

    it("rejects a file that recorded no start time") { expect(probe.verified?(file.with(started: nil))).to be(false) }

    it("rejects a pid that is gone") { expect(probe.verified?(file.with(pid: 7))).to be(false) }
  end

  describe "the real ps" do
    subject(:probe) { described_class.new }

    it("sees this process start") { expect(probe.started(Process.pid)).to match(/\A\w{3} \w{3} [ \d]\d \d\d:\d\d:\d\d \d{4}\z/) }

    context "with a pid that is gone" do
      let(:pid) { Process.spawn("true").tap { Process.wait(it) } }

      it { expect(probe.seen(pid)).to be_nil }
    end

    context "without a ps to ask" do
      before { allow(Open3).to receive(:capture2).and_raise(Errno::ENOENT) }

      it { expect(probe.seen(Process.pid)).to be_nil }
    end
  end
end
