# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::AgentSupervisor::Records do
  subject(:records) { described_class.new(options) }

  let(:dir) { Dir.mktmpdir("records") }
  let(:options) do
    OpenLanes::Execution::AgentSupervisor::Options.new(root: dir,
      plan: "005.00",
      agent: "backend-coder",
      output: File.join(dir, "a.out"),
      status: File.join(dir, "a.status"),
      pid_file: File.join(dir, "pids", "a.pid"),
      argv: %w[true])
  end
  let(:written) { JSON.parse(File.read(options.pid_file)) }

  after { FileUtils.rm_rf(dir) }

  describe "#pid_file" do
    before { records.pid_file(4242) }

    it("names the CLI as its child") { expect(written).to include("role" => "agent", "child" => 4242, "plans" => ["005.00"]) }
    it("records when it started") { expect(written["started"]).to be_a(String) }
    it("leaves no temporary file") { expect(Dir.children(File.dirname(options.pid_file))).to eq(["a.pid"]) }
  end

  context "when ps cannot be run" do
    before do
      allow(Open3).to receive(:capture2).and_raise(Errno::ENOENT)
      records.pid_file(4242)
    end

    it("leaves the start time out") { expect(written).not_to have_key("started") }
  end

  describe "#status" do
    before { records.status(termsig: 9) }

    it("writes it as JSON") { expect(JSON.parse(File.read(options.status))).to eq("termsig" => 9) }
  end
end
