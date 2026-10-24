# frozen_string_literal: true

RSpec.describe "docs/events.md" do
  let(:root) { File.expand_path("../../..", __dir__) }
  let(:doc) { File.read(File.join(root, "docs/events.md")) }

  it "names the three multi-machine points" do
    expect(doc).to include("One writer per file", "Late arrival", "Nothing is rewritten")
  end

  it "documents the config key and what is never stored" do
    expect(doc).to include("events:", "XDG_STATE_HOME", "total_cost_usd")
  end

  it "is linked from the README" do
    expect(File.read(File.join(root, "README.md"))).to include("docs/events.md")
  end
end
