# frozen_string_literal: true

# .openlanes/config.example.yml is what a person copies from, so a key renamed
# in Config or a new agent left out of it would mislead them silently.
RSpec.describe ".openlanes/config.example.yml" do
  let(:path) { File.join(REPO_ROOT, ".openlanes", "config.example.yml") }
  let(:text) { File.read(path) }
  let(:shipped) { Dir[File.join(REPO_ROOT, "agents", "*.md")].map { File.basename(it, ".md") } }

  it "parses as a project's settings" do
    expect { OpenLanes::Config.parse(text, path:) }.not_to raise_error
  end

  it "names every shipped agent, and no other" do
    expect(YAML.safe_load(text, permitted_classes: [Date])["agents"].keys).to match_array(shipped)
  end
end
