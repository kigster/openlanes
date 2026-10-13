# frozen_string_literal: true

require "open3"

RSpec.describe OpenLanes::Live::Repo do
  describe ".normalise" do
    {
      "git@github.com:Kigster/OpenLanes.git"          => "github.com/kigster/openlanes",
      "https://github.com/kigster/openlanes"          => "github.com/kigster/openlanes",
      "https://github.com/kigster/openlanes.git/"     => "github.com/kigster/openlanes",
      "ssh://git@github.com/kigster/openlanes.git"    => "github.com/kigster/openlanes",
      "ssh://git@github.com:22/kigster/openlanes.git" => "github.com/kigster/openlanes",
      "https://user:token@github.com/o/n"             => "github.com/o/n"
    }.each do |url, expected|
      it "folds #{url}" do
        expect(described_class.normalise(url)).to eq(expected)
      end
    end

    it "makes nothing of a string that is not a remote" do
      expect(described_class.normalise("just-a-name")).to be_nil
    end
  end

  describe ".for" do
    let(:dir) { Dir.mktmpdir("openlanes-repo") }
    let(:root) { File.join(dir, "my-clone").tap { FileUtils.mkdir_p(it) } }

    after { FileUtils.rm_rf(dir) }

    def git(*) = Open3.capture2e("git", "-C", root, *)

    it "reads origin" do
      git("init", "-q")
      git("remote", "add", "origin", "git@github.com:Example/Thing.git")
      expect(described_class.for(root)).to eq("github.com/example/thing")
    end

    it "falls back to the directory's name and a digest of its path with no remote to share" do
      expect(described_class.for(root)).to eq("local/my-clone-#{Digest::SHA256.hexdigest(File.realpath(root))[0, 12]}")
    end

    it "tells apart two clones with the same name" do
      other = File.join(Dir.mktmpdir("openlanes-repo"), "my-clone")
      FileUtils.mkdir_p(other)
      expect(described_class.for(other)).not_to eq(described_class.for(root))
    end

    it "falls back to the path it was given when the directory is not there" do
      gone = File.join(root, "gone")
      expect(described_class.for(gone)).to eq("local/gone-#{Digest::SHA256.hexdigest(gone)[0, 12]}")
    end
  end
end
