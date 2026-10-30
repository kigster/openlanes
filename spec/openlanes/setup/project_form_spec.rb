# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::ProjectForm do
  let(:definition) { described_class.definition }
  let(:parsed) { JSON.parse(described_class.to_json) }

  it "passes Inquirex's own validation" do
    expect { Inquirex::TTY::Commands::Validate.new.call(flow_file: described_class::DSL) }.to output(/valid/i).to_stdout
  end

  it "generates the JSON the web front ends read" do
    expect(parsed).to include("id" => "openlanes-init", "start" => "detail").and include("steps" => hash_including("target_ci"))
  end

  it "reads back from its own JSON" do
    expect(Inquirex::Definition.from_json(described_class.to_json).step_ids).to eq(definition.step_ids)
  end

  it "asks about every attribute, now and wanted" do
    OpenLanes::Setup::Architecture::ATTRIBUTES.each do |attribute|
      expect(definition.step_ids).to include(:"current_#{attribute.name}", :"target_#{attribute.name}")
    end
  end

  it "offers more than one thing to pick more often than one" do
    kinds = definition.step_ids.map { definition.step(it) }.select { it.respond_to?(:type) }.map(&:type)
    expect(kinds.count(:multi_enum)).to be > kinds.count(:enum)
  end

  it "lets an extraction fill every wanted attribute" do
    fields = definition.step(:understanding).schema.to_h.keys.map(&:to_sym)
    expect(fields).to include(*OpenLanes::Setup::Extractor::FIELDS.keys)
  end

  describe ".width" do
    it "stops at 115 on a wide screen" do
      expect(described_class.width(200)).to eq(115)
    end

    it "stays inside a narrow one" do
      expect(described_class.width(60)).to eq(59)
    end
  end

  describe ".wrap" do
    subject(:wrapped) { described_class.wrap("word " * 60, 40) }

    it "keeps every line inside the columns" do
      expect(wrapped.lines.map { it.chomp.length }).to all(be <= 40)
    end

    it "loses no word" do
      expect(wrapped.split).to eq(Array.new(60, "word"))
    end
  end

  it "wraps every question inside the limit" do
    questions = definition.step_ids.map { definition.step(it) }.filter_map { it.question if it.respond_to?(:question) }
    expect(questions.flat_map { described_class.wrap(it, 115).lines }.map { it.chomp.length }).to all(be <= 115)
  end
end
