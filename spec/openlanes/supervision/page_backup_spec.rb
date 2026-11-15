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

  it "takes away what the build added, in whatever directory" do
    backup = described_class.new(dist).keep
    FileUtils.mkdir_p(File.join(dist, "assets"))
    File.write(File.join(dist, "assets", "new.js"), "half a bundle")
    backup.restore
    expect(Dir.glob("**/*", base: dist)).to eq(["index.html"])
  end

  # Issue 253: an installed gem's page, read-only to this user.
  describe "a page that cannot be written" do
    let(:made) { [] }
    let(:backup) { described_class.new(dist) }

    before do
      FileUtils.mkdir_p(File.join(dist, "assets"))
      File.write(File.join(dist, "assets", "a.js"), "old js")
      allow(Dir).to(receive(:mktmpdir).and_wrap_original { |original, *args| original.call(*args).tap { made << it } })
      backup.keep
    end

    after { FileUtils.chmod_R("u+w", File.dirname(dist)) }

    it "is left alone when the build never touched it, and the copy let go of" do
      skip "root writes anywhere" if Process.uid.zero?
      FileUtils.chmod_R("a-w", File.dirname(dist))
      expect { backup.restore }.not_to raise_error
      aggregate_failures do
        expect(File.read(File.join(dist, "assets", "a.js"))).to eq("old js")
        expect(File.exist?(made.first)).to be(false)
      end
    end

    it "lets go of the copy even when the page cannot be put back" do
      skip "root writes anywhere" if Process.uid.zero?
      File.write(File.join(dist, "index.html"), "half a page")
      File.chmod(0o555, File.dirname(dist))
      aggregate_failures do
        expect { backup.restore }.to raise_error(SystemCallError)
        expect(File.exist?(made.first)).to be(false)
        expect(File.read(File.join(dist, "index.html"))).to eq("half a page")
      end
    end
  end

  it "keeps nothing when there is no page yet" do
    FileUtils.rm_rf(dist)
    described_class.new(dist).keep.restore
    expect(File.exist?(dist)).to be(false)
  end
end
