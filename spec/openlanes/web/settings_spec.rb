# frozen_string_literal: true

require "digest"
require "tmpdir"

RSpec.describe OpenLanes::Web::Settings do
  let(:root) { Dir.mktmpdir("settings") }
  let(:file) { File.join(root, OpenLanes::Config::FILE) }

  after { FileUtils.rm_rf(root) }

  describe ".read" do
    it "answers the schema, the keys in Config::KEYS order, the file's values and the defaults" do
      File.write(file, "jobs: 3\nmerge:\n  by: human\n")
      view = described_class.read(root)

      expect(view.schema).to eq(OpenLanes::Config::Schema.document)
      expect(view.keys).to eq(OpenLanes::Config::KEYS)
      expect(view.values).to eq("jobs" => 3, "merge" => { "by" => "human" })
      expect(view.defaults).to eq(OpenLanes::Config::Schema.defaults)
      expect(view.etag).to eq(Digest::SHA256.hexdigest("jobs: 3\nmerge:\n  by: human\n"))
      expect(view.to_json_hash.keys).to eq(%i[schema keys values defaults etag branch])
    end

    it "carries one schema node per command, for the commands sub-panes" do
      commands = described_class.read(root).schema.dig("properties", "commands", "properties")
      expect(commands).to include("run")
    end

    it "reads a missing file as empty, and its etag as that of nothing" do
      view = described_class.read(root)
      expect(view.values).to eq({})
      expect(view.etag).to eq(Digest::SHA256.hexdigest(""))
      expect(view.branch).to be_nil
    end

    it "reads a file that is not a mapping, or not YAML, as empty" do
      File.write(file, "- one\n")
      expect(described_class.read(root).values).to eq({})
      File.write(file, "jobs: [\n")
      expect(described_class.read(root).values).to eq({})
    end

    it "names the branch the checkout is on" do
      system("git", "init", "-q", "--initial-branch=main", root, out: File::NULL, err: File::NULL)
      expect(described_class.read(root).branch).to eq("main")
    end
  end

  describe ".validate" do
    it "accepts what Config.parse accepts, unset spelled any way" do
      expect(described_class.validate({ "jobs" => 2, "project" => "", "merge" => { "by" => nil } })).to eq([])
    end

    it "places a schema refusal on its key path" do
      problems = described_class.validate({ "merge" => { "by" => "robot" } })
      expect(problems.map(&:path)).to eq([%w[merge by]])
      expect(problems.first.message).to match(/\S/)
    end

    it "places a parser refusal on the key it names" do
      problems = described_class.validate({ "jobs" => 0 })
      expect(problems.map(&:path)).to eq([["jobs"]])
    end

    it "keeps a refusal that names no key, on the whole file" do
      problem = described_class.parser_problem(".openlanes.yml: expected a mapping of settings at the top")
      expect(problem.to_json_hash).to eq(path: [], message: "expected a mapping of settings at the top")
    end
  end
end
