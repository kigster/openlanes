# frozen_string_literal: true

# Waiting on a child with a limit, against a double: nothing is spawned.
RSpec.describe OpenLanes::Execution::Deadline do
  let(:status) { instance_double(Process::Status) }
  let(:child) { instance_double(OpenLanes::Execution::Child, wait: status) }

  it "waits for a child that ends in time, and never ends it" do
    allow(child).to receive(:terminate)
    read = false
    expect(described_class.wait(child, 5) { read = true }).to eq([status, false])
    expect(read).to be(true)
    expect(child).not_to have_received(:terminate)
  end

  it "ends a child that runs past its time, and says so" do
    ended = false
    allow(child).to receive(:terminate) { ended = true }
    expect(described_class.wait(child, 0.05) { sleep 0.01 until ended }).to eq([status, true])
  end

  it "stops watching when the read fails" do
    allow(child).to receive(:terminate)
    expect { described_class.wait(child, 0.05) { raise IOError, "closed" } }.to raise_error(IOError)
    sleep 0.1
    expect(child).not_to have_received(:terminate)
  end
end
