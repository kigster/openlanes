# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::PidDir do
  subject(:dir) { described_class.new(File.join(root, "tmp", "pids")) }

  let(:root) { Dir.mktmpdir("pid-dir") }
  let(:engine) { OpenLanes::Supervision::PidFile.new(role: "engine", pid: 11, started: "x", root:) }
  let(:run) { OpenLanes::Supervision::PidFile.new(role: "run", pid: 12, started: "x", root:, plans: ["005"]) }
  let(:supervisor) { OpenLanes::Supervision::PidFile.new(role: "supervisor", pid: 10, started: "x", root:) }

  after { FileUtils.rm_rf(root) }

  describe ".for" do
    it("is tmp/pids under the root") { expect(described_class.for(root, env: {}).path).to eq(File.join(root, "tmp", "pids")) }

    it("answers to $OPENLANES_PID_DIR alone") do
      expect(described_class.for(root, env: { "OPENLANES_PID_DIR" => "/var/pids" }).path).to eq("/var/pids")
    end

    it("reads a relative override from the root") do
      expect(described_class.for(root, env: { "OPENLANES_PID_DIR" => "pids" }).path).to eq(File.join(root, "pids"))
    end

    it("ignores a blank override") { expect(described_class.for(root, env: { "OPENLANES_PID_DIR" => " " }).path).to end_with("tmp/pids") }
  end

  describe "#write and #read" do
    before { [run, engine, supervisor].each { dir.write(it) } }

    it { expect(dir.read("engine")).to eq(engine) }

    it("finds a run by its pid") { expect(dir.read("run", pid: 12)).to eq(run) }

    it("reads nothing that is not there") { expect(dir.read("web")).to be_nil }

    it("leaves no temp file behind") { expect(Dir.children(dir.path)).to contain_exactly("engine.pid", "run-12.pid", "supervisor.pid") }

    it("lists the supervisor first and runs last") do
      expect(dir.entries.map { it.file.role }).to eq(%w[supervisor engine run])
    end
  end

  describe "#remove" do
    before { dir.write(engine) }

    it "removes the file that names this process" do
      dir.remove(engine)
      expect(dir.read("engine")).to be_nil
    end

    it "leaves a newer process's file alone" do
      dir.remove(engine.with(pid: 99))
      expect(dir.read("engine")).to eq(engine)
    end
  end

  describe "#entries" do
    before do
      FileUtils.mkdir_p(dir.path)
      File.write(File.join(dir.path, "web.pid"), "not json")
    end

    it("lists an unreadable file with nothing in it") { expect(dir.entries.map(&:file)).to eq([nil]) }

    it("is empty for a directory never made") { expect(described_class.new(File.join(root, "none")).entries).to be_empty }
  end
end
