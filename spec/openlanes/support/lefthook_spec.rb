# frozen_string_literal: true

require "yaml"

# #196 merged lib/ changes without regenerating docs/architecture, and
# architecture_doc_spec failed on main. The pre-commit hook now regenerates
# the docs; this holds the job's shape in place.
RSpec.describe "lefthook.yml" do
  let(:config) { YAML.safe_load_file(File.expand_path("../../../lefthook.yml", __dir__)) }
  let(:job) { config.dig("pre-commit", "jobs").find { |j| j["name"] == "architecture" } }

  it "has a pre-commit job named architecture" do
    expect(job).not_to be_nil
  end

  it "runs at the repository root, where lib/ and the justfile are" do
    expect(job).not_to have_key("root")
  end

  it "fires on staged Ruby under lib/" do
    expect(job["glob"]).to eq("lib/**/*.rb")
  end

  it "regenerates the docs, then stages them itself" do
    expect(job["run"]).to match(%r{just update-architecture\s*&&\s*git add docs/architecture\b})
  end

  it "leaves restaging to its own git add, since stage_fixed misses the docs" do
    expect(job).not_to have_key("stage_fixed")
  end
end
