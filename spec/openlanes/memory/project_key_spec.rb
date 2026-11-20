# frozen_string_literal: true

# The key a project is tagged with in the global store: the same project
# however it was cloned, and never a credential.
RSpec.describe OpenLanes::Memory::ProjectKey do
  {
    "git@github.com:example/repo.git"              => "github.com/example/repo",
    "https://github.com/example/repo.git"          => "github.com/example/repo",
    "https://user:s3cret@GitHub.com/example/repo/" => "github.com/example/repo",
    "ssh://git@github.com:22/example/repo.git"     => "github.com/example/repo",
    "/srv/git/repo.git"                            => "/srv/git/repo"
  }.each do |url, key|
    it "reads #{url} as #{key}" do
      expect(described_class.normalise(url)).to eq(key)
    end
  end

  it "is nil for an empty remote" do
    expect(described_class.normalise(" ")).to be_nil
  end

  it "keeps a remote URI cannot parse as a path, rather than raising" do
    expect(described_class.normalise("https://exa mple.com/repo.git")).to eq("/https://exa mple.com/repo")
  end

  describe ".for" do
    let(:root) { Dir.mktmpdir("project") }

    after { FileUtils.rm_rf(root) }

    it "is the origin remote, normalised" do
      lessons_git(root, "init", "-q", "-b", "main")
      lessons_git(root, "remote", "add", "origin", "git@github.com:example/repo.git")

      expect(described_class.for(root)).to eq("github.com/example/repo")
    end

    it "is the real path of the root when there is no remote" do
      expect(described_class.for(root)).to eq(File.realpath(root))
    end

    it "is the expanded root when git cannot be run" do
      allow(Open3).to receive(:capture2).and_raise(Errno::ENOENT)

      expect(described_class.for(root)).to eq(File.expand_path(root))
    end
  end
end
