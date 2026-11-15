# frozen_string_literal: true

# The schema is the one list of keys (S4); these examples are what stop it
# drifting from the parser that reads the file.
RSpec.describe OpenLanes::Config::Schema do
  let(:document) { described_class.document }
  let(:sections) do
    { "redis_backoff" => OpenLanes::Config::BACKOFF_KEYS, "merge" => OpenLanes::Config::MERGE_KEYS,
      "plans" => OpenLanes::Config::PLAN_KEYS, "questions" => OpenLanes::Config::QUESTION_KEYS,
      "events" => OpenLanes::Config::EVENT_KEYS, "refactor" => OpenLanes::Config::REFACTOR_KEYS,
      "review" => OpenLanes::Config::REVIEW_KEYS, "ci" => %w[provider config],
      "stack" => OpenLanes::Config::STACK_FIELDS.map(&:to_s) }
  end

  def leaves(properties) = properties.flat_map { |key, schema| schema["properties"] && key != "commands" ? leaves(schema["properties"]) : [[key, schema]] }

  it("is a valid draft 2020-12 schema") { expect(JSONSchemer.draft202012.valid?(document)).to be(true) }
  it("holds exactly the top-level keys Config.parse accepts") { expect(described_class.keys).to match_array(OpenLanes::Config::KEYS) }

  it "holds exactly each nested section's keys" do
    expect(sections.to_h { |section, _| [section, described_class.keys_for(section)] }).to eq(sections)
  end

  it "fails when a key is missing or extra" do
    stripped = document.merge("properties" => document["properties"].except("jobs").merge("bogus" => {}))
    expect(stripped["properties"].keys).not_to match_array(OpenLanes::Config::KEYS)
  end

  it "gives every leaf a description and a default" do
    expect(leaves(document["properties"]).reject { |_, s| s.key?("description") && s.key?("default") }).to be_empty
  end

  it("lists the adapters Adapters knows") { expect(document.dig("properties", "adapter", "enum").compact).to eq(OpenLanes::Adapters.names) }
  it("lists the starts Spec knows") { expect(document.dig("properties", "starts", "enum").compact).to eq(OpenLanes::Plans::Spec::STARTS.map(&:to_s)) }
  it("lists the qualities") { expect(document.dig("properties", "desired_codebase_quality", "enum").compact).to eq(OpenLanes::Config::QUALITIES.map(&:to_s)) }
  it("lists the CI providers") { expect(document.dig("properties", "ci", "properties", "provider", "enum").compact).to eq(OpenLanes::Config::CI_PROVIDERS.map(&:to_s)) }

  it "is checked in as it is built, so an editor validates against the real thing" do
    expect(JSON.parse(File.read(described_class::PATH))).to eq(document), "run `just update-config-schema`"
  end

  it "accepts dates and symbols as YAML hands them over" do
    expect(described_class.errors({ "plans" => { "aging_since" => Date.new(2026, 10, 1) }, "starts" => :planning })).to be_empty
  end

  it("refuses a value outside its enum") { expect(described_class.errors({ "merge" => { "by" => "robot" } })).not_to be_empty }
  it("refuses an unknown nested key") { expect(described_class.errors({ "events" => { "colour" => 1 } })).not_to be_empty }

  it "writes the document" do
    path = File.join(Dir.mktmpdir, "s.json")
    described_class.write(path)
    expect(JSON.parse(File.read(path))).to eq(document)
  end

  it "has a default for every key" do
    expect(described_class.defaults).to include("jobs" => nil, "events" => { "enabled" => false, "dir" => nil }, "commands" => {})
  end
end
