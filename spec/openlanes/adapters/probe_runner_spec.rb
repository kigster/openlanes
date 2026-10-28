# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Adapters::ProbeRunner do
  subject(:runner) { described_class.new(timeout: 5) }

  describe "#call" do
    context "with a command that finishes" do
      subject(:result) { runner.call("sh", "-c", "echo out; echo err >&2; exit 3") }

      it { expect([result.stdout, result.stderr, result.status]).to eq(["out\n", "err\n", 3]) }
      it { is_expected.not_to be_ok }
      it { is_expected.not_to be_timed_out }
    end

    context "with a command that succeeds" do
      subject(:result) { runner.call("true") }

      it { is_expected.to be_ok }
    end

    context "with a command that hangs" do
      subject(:result) { described_class.new(timeout: 0.2).call("sleep", "30") }

      it { is_expected.to be_timed_out }
      it { expect(result.stderr).to eq("timed out after 0.2s") }
    end

    context "with a command that cannot start" do
      subject(:result) { runner.call("/nonexistent/openlanes-probe") }

      it { is_expected.to be_timed_out }
      it { expect(result.stderr).to include('No such file') }
    end
  end

  describe "#which" do
    let(:bin) { Dir.mktmpdir("openlanes-probe-path") }

    before do
      File.write(File.join(bin, "claude"), "#!/bin/sh\n")
      File.chmod(0o755, File.join(bin, "claude"))
      File.write(File.join(bin, "codex"), "not executable")
      Dir.mkdir(File.join(bin, "pi"))
    end

    after { FileUtils.rm_rf(bin) }

    it "finds an executable file on the PATH" do
      expect(described_class.new(path: bin).which("claude")).to eq(File.join(bin, "claude"))
    end

    it "skips a file that is not executable, and a directory" do
      expect(%w[codex pi].map { described_class.new(path: bin).which(it) }).to eq([nil, nil])
    end
  end
end
