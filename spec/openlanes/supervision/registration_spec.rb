# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::Registration do
  subject(:registration) do
    described_class.new(draft: OpenLanes::Supervision::PidFile.new(role: "engine", pid: 100, started: nil, root:),
      dir:,
      probe:,
      title: OpenLanes::Supervision::Title.new(role: "engine", root:, setter: ->(text) { titles << text }))
  end

  let(:root) { Dir.mktmpdir("registration") }
  let(:dir) { OpenLanes::Supervision::PidDir.new(File.join(root, "pids")) }
  let(:live) { [] }
  let(:probe) { instance_double(OpenLanes::Supervision::Probe, started: "Mon Oct  5 01:21:45 2026") }
  let(:titles) { [] }
  let(:other) { OpenLanes::Supervision::PidFile.new(role: "engine", pid: 200, started: "x", root:, url: "http://127.0.0.1:11000") }

  before { allow(probe).to receive(:verified?) { live.include?(it.pid) } }

  after { FileUtils.rm_rf(root) }

  describe "#claim" do
    context "with no file" do
      before { registration.claim }

      it("writes its file") { expect(dir.read("engine")).to have_attributes(pid: 100, started: "Mon Oct  5 01:21:45 2026", root:) }
      it("names the process") { expect(titles).to eq(["openlanes-engine [#{File.basename(root)}]"]) }
    end

    context "with a crash's leftover" do
      before do
        dir.write(other)
        registration.claim
      end

      it("writes over it") { expect(dir.read("engine").pid).to eq(100) }
    end

    context "when another live engine holds the file" do
      before do
        dir.write(other)
        live << 200
      end

      it("refuses, naming it") { expect(registration.claim.failure).to have_attributes(status: 75, message: include("pid 200", "http://127.0.0.1:11000")) }
      it("names that holder") { expect(registration.holder).to eq(other) }
    end

    # C1: the lock, not the file, decides. Two claims that both find no
    # file still cannot both win.
    context "when another process holds the lock but has not written its file yet" do
      let(:rival) { dir.lock("engine") }

      before { rival }

      after { rival.close }

      it("refuses as already starting") { expect(registration.claim.failure).to have_attributes(status: 75, message: include("is already starting")) }

      it "writes nothing" do
        registration.claim
        expect(dir.read("engine")).to be_nil
      end
    end

    context "with a second process claiming the same role" do
      let(:second) do
        pid = fork { exit!(registration.claim.success? ? 0 : 1) }
        Process.wait2(pid).last.exitstatus
      end

      before { registration.claim }

      it("refuses it") { expect(second).to eq(1) }
    end

    context "when the holder has released" do
      before { registration.claim.value!.release }

      it("can be claimed again") { expect(registration.claim).to be_success }
    end

    context "when ps cannot give its start time" do
      let(:probe) { instance_double(OpenLanes::Supervision::Probe, started: nil) }

      it("refuses rather than write a file stop could never verify") { expect(registration.claim.failure).to have_attributes(status: 70, message: include("start time")) }

      it "lets go of the lock" do
        registration.claim
        expect(dir.lock("engine")).to be_a(File).and(have_attributes(close: nil))
      end
    end
  end

  describe "#hold" do
    before { registration.claim }

    it("returns what the block did") { expect(registration.hold { 7 }).to eq(7) }

    it "removes the file after the block" do
      registration.hold { nil }
      expect(dir.read("engine")).to be_nil
    end

    it "removes the file on exit, which is how a refusal ends" do
      expect { registration.hold { exit 75 } }.to raise_error(SystemExit)
      expect(dir.read("engine")).to be_nil
    end

    it "leaves the file behind for a crash" do
      expect { registration.hold { raise "boom" } }.to raise_error(RuntimeError)
      expect(dir.read("engine").pid).to eq(100)
    end
  end

  describe "#update" do
    it "rewrites the file" do
      registration.claim
      registration.update(failed: { "web" => "exited 69" })
      expect(dir.read("engine").failed).to eq("web" => "exited 69")
    end

    it "writes nothing before a claim" do
      registration.update(failed: { "web" => "exited 69" })
      expect(dir.read("engine")).to be_nil
    end
  end

  describe "#title" do
    it("adds the status") { expect(registration.title("2 of 4 agents busy")).to end_with("] 2 of 4 agents busy") }
  end
end
