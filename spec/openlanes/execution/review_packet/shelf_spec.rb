# frozen_string_literal: true

# Real directories and real modes: the point of the shelf is what the
# filesystem says about who could have written a packet.
RSpec.describe OpenLanes::Execution::ReviewPacket::Shelf do
  subject(:shelf) { described_class.new(dir:) }

  let(:home) { Dir.mktmpdir("shelf") }
  let(:dir) { File.join(home, "packets") }

  after { FileUtils.rm_rf(home) }

  it "makes its directory this user's alone, and reads back what it kept" do
    shelf.keep("abc-007.00-r3.md", "# Review packet\n")

    expect(File.stat(dir).mode & 0o777).to eq(0o700)
    expect(shelf.read("abc-007.00-r3.md")).to eq("# Review packet\n")
  end

  it "has nothing for a round it never kept" do
    expect(shelf.read("abc-007.00-r3.md")).to be_nil
  end

  it "drops the plan's earlier rounds, and no other plan's" do
    shelf.keep("abc-007.00-r3.md", "three")
    shelf.keep("abc-008.00-r1.md", "other")
    shelf.keep("abc-007.00-r4.md", "four")

    expect(Dir.children(dir).sort).to eq(%w[abc-007.00-r4.md abc-008.00-r1.md])
  end

  it "logs, and does not raise, when the directory cannot be made" do
    File.write(dir, "a file where the directory should be")
    allow(OpenLanes::UI).to receive(:log)

    expect { shelf.keep("abc-007.00-r3.md", "text") }.not_to raise_error
    expect(OpenLanes::UI).to have_received(:log).with(/review packet/, level: :warn)
    expect(shelf.read("abc-007.00-r3.md")).to be_nil
  end

  it "logs, and does not raise, when the packet cannot be written" do
    shelf.keep("abc-007.00-r3.md", "three")
    allow(File).to receive(:write).and_raise(Errno::ENOSPC)
    allow(OpenLanes::UI).to receive(:log)

    shelf.keep("abc-007.00-r4.md", "four")

    expect(OpenLanes::UI).to have_received(:log).with(/could not keep the review packet/, level: :warn)
  end
end
