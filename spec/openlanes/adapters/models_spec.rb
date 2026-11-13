# frozen_string_literal: true

RSpec.describe "The adapters' models" do
  describe OpenLanes::Adapters::Claude do
    subject(:adapter) { described_class.new }

    it "offers every model it ships, Fable at the top, priced as the pricing page says" do
      expect(adapter.models.map(&:wire).first(2)).to eq([
                                                          { id: "claude-fable-5-1", label: "Fable 5.1", rates: { in: 10, out: 50 }, context: 1_000_000, estimated: false },
                                                          { id: "claude-fable-5", label: "Fable 5", rates: { in: 10, out: 50 }, context: 1_000_000, estimated: false }
                                                        ])
    end

    it "puts Fable on the menu" do
      expect([adapter.model_entry("fable")&.id, adapter.model_entry("claude-fable-5-1")&.id])
        .to eq(%w[claude-fable-5-1 claude-fable-5-1])
    end

    it "gives every model a context window" do
      expect(adapter.models.map(&:context).uniq.sort).to eq([200_000, 1_000_000])
    end

    it "resolves a full id, an alias, and no name to a model" do
      expect([adapter.model_entry("claude-haiku-5-5"), adapter.model_entry("opus"), adapter.model_entry(nil),
              adapter.model_entry("default"), adapter.model_entry("gpt-5")].map { it&.id })
        .to eq(["claude-haiku-5-5", "claude-opus-5-5", "claude-sonnet-5-5", "claude-sonnet-5-5", nil])
    end

    it "takes an alias only when it is exactly a tier" do
      expect(%w[not-opus sonnet-old claude-opus].map { adapter.model_entry(it) }).to eq([nil, nil, nil])
    end

    it "prices a model it has never seen at its tier's rate, and says the price is a guess" do
      entry = adapter.model_entry("claude-opus-6")
      expect([entry.label, entry.rate_in, entry.rate_out, entry.estimated]).to eq(["Opus 6", 4, 20, true])
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
