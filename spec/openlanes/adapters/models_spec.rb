# frozen_string_literal: true

RSpec.describe "The adapters' models" do
  describe OpenLanes::Adapters::Claude do
    subject(:adapter) { described_class.new }

    it "offers only what may run, most capable first, priced as the pricing page says" do
      expect(adapter.models.map(&:wire).first(2)).to eq([
                                                          { id: "claude-opus-5-5", label: "Opus 5.5", rates: { in: 4, out: 20 }, context: 200_000 },
                                                          { id: "claude-opus-5", label: "Opus 5", rates: { in: 5, out: 25 }, context: 200_000 }
                                                        ])
    end

    it "keeps Fable priced, but off the menu while Opus is the ceiling" do
      expect([described_class::CATALOGUE.first.id, adapter.model_entry("fable"), adapter.model_entry("claude-fable-5-1")])
        .to eq(["claude-fable-5-1", nil, nil])
    end

    it "gives every model a context window" do
      expect(adapter.models.map(&:context).uniq).to eq([200_000])
    end

    it "resolves a full id, an alias, and no name to a model" do
      expect([adapter.model_entry("claude-haiku-5-5"), adapter.model_entry("opus"), adapter.model_entry(nil),
              adapter.model_entry("default"), adapter.model_entry("gpt-5")].map { it&.id })
        .to eq(["claude-haiku-5-5", "claude-opus-5-5", "claude-sonnet-5-5", "claude-sonnet-5-5", nil])
    end

    it "takes an alias only when it is exactly a tier" do
      expect(%w[not-opus sonnet-old claude-opus].map { adapter.model_entry(it) }).to eq([nil, nil, nil])
    end

    it "sets its autocompact threshold for the child" do
      expect(adapter.environment).to eq("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" => "40")
    end

    it "prices tokens per million" do
      expect(adapter.model_entry("sonnet").cost(1_000_000, 100_000)).to eq(3.0)
    end
  end

  describe OpenLanes::Adapters::Codex do
    subject(:adapter) { described_class.new }

    it "offers nothing it has no prices for, and adds nothing to the environment" do
      expect([adapter.models, adapter.model_entry("gpt-5"), adapter.environment]).to eq([[], nil, {}])
    end
  end
end
