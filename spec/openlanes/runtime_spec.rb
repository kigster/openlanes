# frozen_string_literal: true

RSpec.describe OpenLanes::Runtime do
  describe ".state_home" do
    it "falls back to ~/.local/state when XDG_STATE_HOME is unset" do
      expect(described_class.state_home({})).to eq(File.join(Dir.home, ".local", "state"))
    end

    it "ignores an empty value" do
      expect(described_class.state_home({ "XDG_STATE_HOME" => "" })).to eq(File.join(Dir.home, ".local", "state"))
    end

    it "ignores a relative value" do
      expect(described_class.state_home({ "XDG_STATE_HOME" => "rel/state" })).to eq(File.join(Dir.home, ".local", "state"))
    end

    it "uses an absolute value" do
      expect(described_class.state_home({ "XDG_STATE_HOME" => "/srv/state" })).to eq("/srv/state")
    end
  end

  describe ".dir" do
    let(:tmp) { File.realpath(Dir.mktmpdir("runtime")) }
    let(:one) { File.join(tmp, "one").tap { FileUtils.mkdir_p(it) } }
    let(:two) { File.join(tmp, "two").tap { FileUtils.mkdir_p(it) } }

    after { FileUtils.rm_rf(tmp) }

    it "lives under the state home, named for the root" do
      expect(described_class.dir(root: one)).to start_with(File.join(described_class.state_home, "openlanes", "one-"))
    end

    it "gives two roots two directories" do
      expect(described_class.dir(root: one)).not_to eq(described_class.dir(root: two))
    end

    it "gives the same root through a symlink one directory" do
      link = File.join(tmp, "link")
      File.symlink(one, link)
      expect(described_class.dir(root: link)).to eq(described_class.dir(root: one))
    end

    it "creates the locks directory on demand" do
      expect(File.directory?(described_class.locks_dir(root: one))).to be(true)
    end

    it "puts the state file in it" do
      expect(described_class.state_file(root: one)).to eq(File.join(described_class.dir(root: one), "openlanes-state.json"))
    end
  end
end
