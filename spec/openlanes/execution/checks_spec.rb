# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Real files in a temp directory: the command comes from what the checkout
# holds, so faking the filesystem would test the fake.
RSpec.describe OpenLanes::Execution::Checks do
  let(:root) { Dir.mktmpdir("openlanes-checks") }

  after { FileUtils.rm_rf(root) }

  def write(name, text) = File.write(File.join(root, name), text)

  describe ".commands" do
    subject(:commands) { described_class.commands(root) }

    it "prefers just check-all when the justfile has that recipe" do
      write("justfile", "set shell := [\"bash\", \"-c\"]\n\n# everything\ncheck-all: lint test\n")
      write("Gemfile", "source 'https://rubygems.org'\n")

      expect(commands).to eq(["just check-all"])
    end

    it "reads a quiet recipe with parameters" do
      write("Justfile", "@check-all *args:\n  just test {{args}}\n")

      expect(commands).to eq(["just check-all"])
    end

    it "is not fooled by an assignment of the same name" do
      write("justfile", "check-all := \"no\"\n")

      expect(commands).to eq([])
    end

    it "falls back to rspec and rubocop in a Ruby project" do
      write("justfile", "test:\n  bundle exec rspec\n")
      write("Gemfile", "source 'https://rubygems.org'\n")

      expect(commands).to eq(["bundle exec rspec", "bundle exec rubocop"])
    end

    it "names nothing in a project it cannot read" do
      expect(commands).to eq([])
    end
  end

  describe ".requirement" do
    it "names the one command" do
      write("justfile", "check-all:\n  true\n")

      expect(described_class.requirement(root)).to include("`just check-all` exits 0", "Run it before you sign Completed")
    end

    it "names both Ruby commands" do
      write("Gemfile", "")

      expect(described_class.requirement(root)).to include("`bundle exec rspec` and `bundle exec rubocop` each exit 0")
    end
  end

  describe ".apply_to?" do
    it "holds builders and the reviewer to it" do
      %w[backend-coder frontend-coder chores-coder staff-reviewer].each do |name|
        expect(described_class.apply_to?(OpenLanes::Agents.find(name))).to be(true), name
      end
    end

    it "spares the agents that write documents" do
      %w[researcher spec-writer planner unblocker].each do |name|
        expect(described_class.apply_to?(OpenLanes::Agents.find(name))).to be(false), name
      end
    end
  end
end
