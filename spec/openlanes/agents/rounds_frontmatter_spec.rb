# frozen_string_literal: true

require "yaml"

# The rounds table in docs/WORKFLOW.md is generated from these lines, so an
# agent without one would show the registry's fallback as if somebody chose it.
RSpec.describe "agents/*.md rounds: frontmatter" do
  Dir[File.expand_path("../../../agents/*.md", __dir__)].each do |path|
    it "#{File.basename(path)} states its own rounds:" do
      meta = YAML.safe_load(File.read(path)[/\A---\n(.*?)\n---\n/m, 1])
      expect(meta["rounds"]).to be_between(1, OpenLanes::Agents::Agent::MAX_ROUNDS)
    end
  end
end
