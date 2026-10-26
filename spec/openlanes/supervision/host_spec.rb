# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::Host do
  describe "WAITER" do
    subject(:waiter) { described_class::WAITER }

    context "with a child that ended" do
      let(:pid) { Process.spawn("exit 3") }
      let(:status) do
        Timeout.timeout(5) do
          sleep(0.01) until (found = waiter.call(pid))
          found
        end
      end

      it("reaps it and returns its status") { expect(status.exitstatus).to eq(3) }
    end

    context "with a child still running" do
      let(:pid) { Process.spawn("sleep", "5") }

      after { Process.kill("KILL", pid) && Process.wait(pid) }

      it { expect(waiter.call(pid)).to be_nil }
    end

    context "with a pid that is no child of this process" do
      it { expect(waiter.call(1)).to eq(:gone) }
    end
  end

  describe "SIGNALLER" do
    subject(:signaller) { described_class::SIGNALLER }

    context "with a pid that is gone" do
      let(:pid) { Process.spawn("true").tap { Process.wait(it) } }

      it("reports nothing") { expect(signaller.call("TERM", pid)).to be_nil }
    end
  end

  describe ".on_purpose?" do
    subject { described_class.on_purpose?(status) }

    context "with exit 0" do
      let(:status) { instance_double(Process::Status, exitstatus: 0) }

      it { is_expected.to be(true) }
    end

    context "with a refusal" do
      let(:status) { instance_double(Process::Status, exitstatus: 69) }

      it { is_expected.to be(true) }
    end

    context "with an unhandled error's exit 1" do
      let(:status) { instance_double(Process::Status, exitstatus: 1) }

      it { is_expected.to be(false) }
    end

    context "with a signal" do
      let(:status) { instance_double(Process::Status, exitstatus: nil) }

      it { is_expected.to be(false) }
    end

    context "with one that was gone" do
      let(:status) { :gone }

      it { is_expected.to be(false) }
    end
  end

  describe ".describe" do
    subject { described_class.describe(status) }

    context "with a child that exited" do
      let(:status) { instance_double(Process::Status, signaled?: false, exitstatus: 3) }

      it { is_expected.to eq("exit 3") }
    end

    context "with a child that was killed" do
      let(:status) { instance_double(Process::Status, signaled?: true, termsig: 9) }

      it { is_expected.to eq("signal 9") }
    end

    context "with one that was gone" do
      let(:status) { :gone }

      it { is_expected.to eq("gone") }
    end
  end

  describe "SYSTEM" do
    subject { described_class::SYSTEM }

    it { is_expected.to have_attributes(spawner: OpenLanes::Spawner::System, clock: OpenLanes::Clock::System) }
  end
end
