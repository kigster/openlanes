# frozen_string_literal: true

require "json_schemer"
require "open3"

# The schema, the writer and the parser together, nothing stubbed: the real
# executable writes the file in a real repository, the checked-in schema
# judges it, and the parser reads it back.
RSpec.describe "the config schema end to end" do
  include SettingsIn

  let(:repo) { File.realpath(Dir.mktmpdir("openlanes-config-schema")) }
  let(:file) { File.join(repo, OpenLanes::Config::FILE) }
  let(:exe) { File.expand_path("../../exe/openlanes", __dir__) }
  let(:schema) { JSONSchemer.schema(JSON.parse(File.read(OpenLanes::Config::Schema::PATH))) }
  let(:written) { YAML.safe_load_file(file, permitted_classes: [Date]) }

  before do
    system("git", "-C", repo, "init", "-q", "-b", "main", exception: true)
    out, err, status = Open3.capture3(exe, "init", "-n", "-y", "--project", "Demo", "--jobs", "3", chdir: repo, stdin_data: "")
    raise "openlanes init failed: #{err}" unless status.success?

    File.write(file, out)
  end

  after { FileUtils.rm_rf(repo) }

  it "writes a file the checked-in schema accepts" do
    expect(schema.validate(written).to_a).to be_empty
  end

  it "writes every key the schema knows, nested ones included" do
    sections = OpenLanes::Config::Schema.keys.reject { OpenLanes::Config::Schema.keys_for(it).empty? || it == "commands" }
    expect([written.keys, sections.to_h { [it, written[it].keys] }])
      .to eq([OpenLanes::Config::Schema.keys, sections.to_h { [it, OpenLanes::Config::Schema.keys_for(it)] }])
  end

  it "loads back into a Config that writes the same file" do
    config = OpenLanes::Config.load(repo)
    expect([config.project, config.jobs, config.to_yaml]).to eq(["Demo", 3, File.read(file)])
  end

  it "refuses a corrupted value in the <path>: <key>: <problem> shape" do
    File.write(file, File.read(file).sub(/^starts: research$/, "starts: sideways"))
    expect { OpenLanes::Config.load(repo) }.to raise_error(OpenLanes::Error, /\A#{Regexp.escape(file)}: starts: "sideways" is not one of /)
  end
end
