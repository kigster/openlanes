# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::PageBackup do
  let(:dist) { File.join(Dir.mktmpdir("page-backup"), "dist") }

  before do
    FileUtils.mkdir_p(dist)
    File.write(File.join(dist, "index.html"), "old page")
  end

  it "puts the kept page back over whatever the build left" do
    backup = described_class.new(dist).keep
    File.write(File.join(dist, "index.html"), "half a page")
    backup.restore
    expect(File.read(File.join(dist, "index.html"))).to eq("old page")
  end

  it "leaves the new page alone when discarded" do
    backup = described_class.new(dist).keep
    File.write(File.join(dist, "index.html"), "new page")
    backup.discard
    backup.restore
    expect(File.read(File.join(dist, "index.html"))).to eq("new page")
  end

  it "keeps nothing when there is no page yet" do
    FileUtils.rm_rf(dist)
    described_class.new(dist).keep.restore
    expect(File.exist?(dist)).to be(false)
  end
end
