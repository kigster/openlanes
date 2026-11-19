# frozen_string_literal: true

# A compaction asked of a handle (W28) is handed to the executor once, is the
# same request while under way, and is refused once the invocation is over.
RSpec.describe OpenLanes::Execution::Executor::Handle::Compacting do
  subject(:handle) { OpenLanes::Execution::Executor::Handle.new }

  let(:dir) { Dir.mktmpdir }
  let(:control) { OpenLanes::Execution::Control.register(dir, "001.00-backend-coder") }
  let(:ended) { Queue.new }
  let(:child) do
    instance_double(OpenLanes::Execution::AgentProcess).tap do |child|
      allow(child).to receive(:terminate) { ended << :terminated }
    end
  end

  after do
    OpenLanes::Execution::Control.reset!
    FileUtils.rm_rf(dir)
  end

  it "has nothing asked of it at first" do
    expect([handle.compaction, handle.take_compaction]).to eq([nil, nil])
  end

  context "with the agent at work" do
    before do
      handle.control = control
      handle.child = child
    end

    let!(:request) { handle.compact!(model: "sonnet", grace: 0) }

    it "writes INTERRUPT so the agent leaves a resume note" do
      expect(File.read(control).strip).to eq("INTERRUPT")
    end

    it "carries the model the session goes on in" do
      expect(request.model).to eq("sonnet")
    end

    it "hands the request to the executor once" do
      expect([handle.take_compaction, handle.take_compaction]).to eq([request, nil])
    end

    it "is the same request when asked again before it is done" do
      expect(handle.compact!(grace: 0)).to equal(request)
    end

    it "terminates the process it was aimed at after the grace" do
      expect(ended.pop(timeout: 2)).to eq(:terminated)
    end

    it "is a new request once the first is done" do
      request.done!("compacted")
      expect(handle.compact!(grace: 0)).not_to equal(request)
    end
  end

  context "when a process has been replaced before the grace is up" do
    it "leaves the new one alone" do
      handle.child = child
      handle.compact!(grace: 0.05)
      handle.child = instance_double(OpenLanes::Execution::AgentProcess)
      sleep(0.2)
      expect(child).not_to have_received(:terminate)
    end
  end

  context "when the invocation is over" do
    it "refuses a request that was not acted on" do
      request = handle.compact!(grace: 0)
      handle.close!
      expect([request.status, request.reason, handle.take_compaction])
        .to eq(["refused", described_class::TOO_LATE, nil])
    end

    it "refuses a request that arrives afterwards" do
      handle.close!
      request = handle.compact!(grace: 0)
      expect([request.finished?, request.reason]).to eq([true, described_class::TOO_LATE])
    end
  end
end
