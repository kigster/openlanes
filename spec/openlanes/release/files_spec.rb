# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe "OpenLanes::Release files" do
  describe OpenLanes::Release::VersionFile do
    let(:file) { described_class.new(%(module OpenLanes\n  VERSION = "4.0.1"\nend\n)) }

    it "reads the assigned version" do
      expect(file.version).to eq("4.0.1")
    end

    it "rewrites only the version, keeping the indentation" do
      expect(file.with("4.0.2")).to eq(%(module OpenLanes\n  VERSION = "4.0.2"\nend\n))
    end

    it "answers nil when there is no assignment" do
      expect(described_class.new("module OpenLanes; end").version).to be_nil
    end

    it "reads the checkout's own version.rb as OpenLanes::VERSION" do
      root = File.expand_path("../../..", __dir__)
      expect(described_class.new(File.read(File.join(root, described_class::PATH))).version).to eq(OpenLanes::VERSION)
    end
  end

  describe OpenLanes::Release::Lockfile do
    let(:lock) { described_class.new("PATH\n  specs:\n    openlanes (1.0.0)\n    other (2.0)\nCHECKSUMS\n  openlanes (1.0.1)\n") }

    it "lists every openlanes entry, and nothing else's" do
      expect(lock.entries).to eq(%w[1.0.0 1.0.1])
    end

    it "lists distinct versions" do
      expect(described_class.new("    openlanes (1.0.0)\n  openlanes (1.0.0)\n").versions).to eq(["1.0.0"])
    end
  end

  describe OpenLanes::Release::Relock do
    it "reports a failed bundle lock, printing its output" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Gemfile"), "raise 'broken'\n")
        err = StringIO.new

        expect(Bundler.with_unbundled_env { described_class.new(dir, err:).call }).to be(false)
        expect(err.string).to include("broken")
      end
    end
  end
end
