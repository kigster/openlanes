# frozen_string_literal: true

# README.md's "Copilot commands" table is written by hand; this holds it to
# Slash::COMMANDS, the table the copilot's usage is built from (plan 069.00).
RSpec.describe "README.md's copilot commands" do
  let(:readme) { File.read(File.expand_path("../../../README.md", __dir__)) }
  let(:section) { readme[/^### Copilot commands\n(.*?)(?=^##)/m, 1].to_s }
  let(:rows) { section.lines.grep(%r{\A\| `/}).map { it.split("|").map(&:strip).reject(&:empty?) } }

  it "lists every slash command, in order, with its syntax and effect" do
    expected = OpenLanes::Live::Copilot::Slash::COMMANDS.map { ["`#{it.syntax}`", it.summary] }
    expect(rows.map { [it.first, it.last] }).to eq(expected)
  end

  it "no longer calls the copilot read-only" do
    expect(readme.lines.grep(/`copilot`/).join).not_to include("read-only")
  end
end
