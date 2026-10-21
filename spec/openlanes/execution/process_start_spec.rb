# frozen_string_literal: true

# B4: a process's start time, from /proc where there is one, from ps otherwise.
RSpec.describe OpenLanes::Execution::ProcessStart do
  let(:no_proc) { "/nonexistent-proc" }
  let(:ok) { instance_double(Process::Status, success?: true) }
  let(:failed) { instance_double(Process::Status, success?: false) }

  it "reads /proc/<pid>/stat, counting fields after the command name" do
    Dir.mktmpdir do |proc_root|
      FileUtils.mkdir_p(File.join(proc_root, "42"))
      fields = ["S"] + Array.new(18, "0") + ["500"] + Array.new(10, "0")
      File.write(File.join(proc_root, "42", "stat"), "42 (odd) name) #{fields.join(" ")}")
      File.write(File.join(proc_root, "uptime"), "1000.00 900.00")
      allow(described_class).to receive(:clock_ticks).and_return(100)
      expect(described_class.of(42, proc_root:)).to be_within(2).of(Time.now - 1000 + 5)
    end
  end

  it "asks ps where there is no /proc" do
    runner = class_double(Open3, capture2: ["Wed Oct 21 10:00:00 2026\n", ok])
    expect(described_class.of(42, proc_root: no_proc, runner:)).to eq(Time.parse("Wed Oct 21 10:00:00 2026"))
    expect(runner).to have_received(:capture2).with("ps", "-o", "lstart=", "-p", "42")
  end

  it "is nil for a dead pid" do
    runner = class_double(Open3, capture2: ["", failed])
    expect(described_class.of(42, proc_root: no_proc, runner:)).to be_nil
  end

  it "is nil when ps cannot run" do
    runner = class_double(Open3)
    allow(runner).to receive(:capture2).and_raise(Errno::ENOENT)
    expect(described_class.of(42, proc_root: no_proc, runner:)).to be_nil
  end

  it "is nil for a pid that is not one" do
    expect(described_class.of(nil)).to be_nil
  end

  it "is nil when ps prints nothing" do
    expect(described_class.of(42, proc_root: no_proc, runner: class_double(Open3, capture2: ["\n", ok]))).to be_nil
  end

  it "reads its own start on this host" do
    expect(described_class.of(Process.pid)).to be_within(86_400).of(Time.now)
  end
end
