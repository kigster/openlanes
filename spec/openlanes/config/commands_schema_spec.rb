# frozen_string_literal: true

# S5: the `commands` schema is read off the registry, so a flag needs no
# second edit anywhere.
RSpec.describe OpenLanes::Config::CommandsSchema do
  let(:schema) { described_class.build }

  it "holds every registered command with exactly the options it declares" do
    declared = described_class.commands(OpenLanes::CLI).transform_values { |c| c.options.map { it.name.to_s }.sort }
    expect(schema["properties"].transform_values { it["properties"].keys.sort }).to eq(declared)
  end

  it("names subcommands in full") { expect(schema["properties"]).to include("resync dirs", "run") }
  it("types a boolean flag") { expect(schema.dig("properties", "run", "properties", "dry_run")).to include("type" => "boolean", "default" => false) }
  it("lets a string flag hold a number, as commands.run.timeout always could") { expect(schema.dig("properties", "run", "properties", "timeout", "type")).to eq(%w[string number]) }

  it "picks up a new option on a throwaway registry with no other edit" do
    command = Class.new(Dry::CLI::Command) do
      desc "Brew it"
      option :strength, type: :string, values: %w[mild strong], default: "mild", desc: "How strong"
      option :cups, type: :integer, desc: "How many"
    end
    registry = Module.new { extend Dry::CLI::Registry }
    registry.register("brew", command)

    expect(described_class.build(registry)["properties"]).to eq("brew" => {
      "type" => "object", "description" => "Brew it", "default" => {}, "additionalProperties" => false,
      "properties" => {
        "cups"     => { "type" => "integer", "description" => "How many" },
        "strength" => { "type" => %w[string number], "enum" => %w[mild strong], "description" => "How strong", "default" => "mild" }
      }
    })
  end

  it "names nothing about the machine it was built on, so the checked-in file is the same everywhere" do
    text = JSON.generate(described_class.build)
    expect([text.include?(Dir.home), text.include?("(installed)")]).to eq([false, false])
  end
end
