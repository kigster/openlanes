# frozen_string_literal: true

# Real directories throughout: the search is nothing but questions asked of
# the filesystem, so faking it would only test the fake.
RSpec.describe OpenLanes::Project do
  let(:top) { File.realpath(Dir.mktmpdir("openlanes-project")) }
  let(:home) { File.join(top, "home") }
  let(:repo) { File.join(top, "work", "repo") }
  let(:deep) { File.join(repo, "lib", "deep") }

  after { FileUtils.rm_rf(top) }

  before { FileUtils.mkdir_p([home, deep]) }

  def touch(*parts)
    path = File.join(*parts)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")
  end

  describe ".root" do
    subject(:root) { described_class.root(from: deep, home:) }

    it "is nil when nothing above marks a project" do
      expect(root).to be_nil
    end

    it "takes the nearest directory holding .plans" do
      FileUtils.mkdir_p(File.join(repo, ".plans"))

      expect(root).to eq(repo)
    end

    it "takes the nearest directory holding .openlanes.yml" do
      touch(repo, "lib", ".openlanes.yml")

      expect(root).to eq(File.join(repo, "lib"))
    end

    it "falls back to the nearest .git, a directory" do
      FileUtils.mkdir_p(File.join(repo, ".git"))

      expect(root).to eq(repo)
    end

    # A worktree has a `.git` file pointing at the main checkout.
    it "falls back to the nearest .git, a file" do
      touch(repo, ".git")

      expect(root).to eq(repo)
    end

    it "prefers a .plans above to a .git below" do
      FileUtils.mkdir_p([File.join(repo, ".git"), File.join(top, "work", ".plans")])

      expect(root).to eq(File.join(top, "work"))
    end

    context "when the search starts under $HOME" do
      subject(:root) { described_class.root(from: File.join(home, "src"), home:) }

      before { FileUtils.mkdir_p(File.join(home, "src")) }

      # A dotfiles repository must not capture every project under it.
      it "never takes $HOME for its .git" do
        FileUtils.mkdir_p(File.join(home, ".git"))

        expect(root).to be_nil
      end

      it "never takes $HOME for its .plans" do
        FileUtils.mkdir_p(File.join(home, ".plans"))

        expect(root).to be_nil
      end

      it "takes $HOME when it holds .openlanes.yml" do
        touch(home, ".openlanes.yml")

        expect(root).to eq(home)
      end
    end
  end

  describe ".init_root" do
    it "is the nearest repository" do
      FileUtils.mkdir_p(File.join(repo, ".git"))

      expect(described_class.init_root(from: deep, home:)).to eq(repo)
    end

    it "is the starting directory when there is no repository" do
      expect(described_class.init_root(from: deep, home:)).to eq(deep)
    end

    it "ignores a .plans it would otherwise stop at" do
      FileUtils.mkdir_p([File.join(repo, ".git"), File.join(deep, ".plans")])

      expect(described_class.init_root(from: deep, home:)).to eq(repo)
    end
  end
end
