# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::Stopper do
  subject(:stopper) { described_class.new(dir:, probe:, host: OpenLanes::Supervision::Host.new(signaller:, clock:)) }

  let(:root) { Dir.mktmpdir("stopper") }
  let(:dir) { OpenLanes::Supervision::PidDir.new(File.join(root, "pids")) }
  let(:clock) { OpenLanes::Clock::Fake.new }
  let(:live) { [10, 11, 12, 20] }
  let(:stubborn) { [] }
  let(:probe) { instance_double(OpenLanes::Supervision::Probe) }
  let(:signals) { [] }
  let(:signaller) do
    lambda do |signal, pid|
      signals << [signal, pid]
      live.delete(pid) unless signal == "TERM" && stubborn.include?(pid)
    end
  end

  def file(role, pid) = OpenLanes::Supervision::PidFile.new(role:, pid:, started: "x", root:)

  before do
    allow(probe).to receive(:verified?) { live.include?(it.pid) }
    [file("supervisor", 10), file("engine", 11), file("web", 12), file("run", 20)].each { dir.write(it) }
  end

  after { FileUtils.rm_rf(root) }

  context "with a live supervisor" do
    # A supervisor stops its children, and they remove their own files.
    before { allow(signaller).to(receive(:call).and_wrap_original { |m, *args| m.call(*args).tap { %w[engine web].each { FileUtils.rm_f(File.join(dir.path, "#{it}.pid")) } } }) }

    let!(:outcomes) { stopper.call }

    it("TERMs the supervisor alone") { expect(signals).to eq([["TERM", 10]]) }
    it("reports it stopped") { expect(outcomes.map(&:result)).to eq(%i[stopped]) }
    it("leaves every run") { expect(dir.entries.map { it.file.role }).to eq(%w[run]) }
  end

  context "with --all" do
    before { stopper.call(runs: true) }

    it("stops every run too") { expect(signals).to include(["TERM", 20]) }
    it("leaves no file behind") { expect(dir.entries).to be_empty }
  end

  context "with an engine and a web whose supervisor is gone" do
    let(:live) { [11, 12] }

    let!(:outcomes) { stopper.call }

    it("stops them") { expect(signals).to eq([["TERM", 11], ["TERM", 12]]) }
    it("reports the supervisor's file stale") { expect(outcomes.map(&:result)).to eq(%i[stale stopped stopped]) }
  end

  context "with a process that outlives TERM" do
    let(:stubborn) { [11] }
    let(:live) { [11] }

    let!(:outcomes) { stopper.call }

    it("KILLs it") { expect(signals.last).to eq(["KILL", 11]) }
    it("after about ten seconds") { expect(clock.monotonic).to be_within(0.2).of(10) }
    it("says so") { expect(outcomes.map(&:result)).to eq(%i[stale killed stale]) }
  end

  context "with a pid now held by some other process" do
    let(:live) { [] }

    before { stopper.call(runs: true) }

    it("signals nothing") { expect(signals).to be_empty }
    it("removes every stale file") { expect(dir.entries).to be_empty }
  end

  context "with an unreadable file" do
    let(:live) { [] }

    before { File.write(File.join(dir.path, "web.pid"), "") }

    it("removes it") { expect(stopper.call.map(&:result)).to all(eq(:stale)) }
  end

  context "with dry_run" do
    let!(:outcomes) { stopper.call(runs: true, dry_run: true) }

    it("signals nothing") { expect(signals).to be_empty }
    it("removes nothing") { expect(dir.entries.size).to eq(4) }
    it("says what it would stop") { expect(outcomes.map(&:result)).to eq(%i[would_stop would_stop would_stop would_stop]) }
  end
end
