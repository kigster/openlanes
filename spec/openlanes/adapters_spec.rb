# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters do
  describe ".for" do
    it "defaults to claude" do
      expect(described_class.for(nil)).to be_a(OpenLanes::Adapters::Claude)
    end

    it "finds codex and pi by name" do
      expect([described_class.for("codex"), described_class.for(:pi)].map(&:name)).to eq(%w[codex pi])
    end

    it "refuses a name nothing answers to" do
      expect { described_class.for("gpt") }.to raise_error(OpenLanes::Error, /unknown adapter "gpt"/)
    end

    it "keeps the unknown-name message byte-identical" do
      expect { described_class.for("gpt") }
        .to raise_error(OpenLanes::Error, 'unknown adapter "gpt"; known: claude, codex, pi, grok, gemini')
    end

    {
      "claude" => OpenLanes::Adapters::Claude,
      "codex"  => OpenLanes::Adapters::Codex,
      "pi"     => OpenLanes::Adapters::Pi,
      "grok"   => OpenLanes::Adapters::Grok,
      "gemini" => OpenLanes::Adapters::Gemini
    }.each do |name, klass|
      it "resolves #{name} from the container as adapters.#{name}" do
        aggregate_failures do
          expect(OpenLanes::Container["adapters.#{name}"]).to be_a(klass)
          expect(described_class.for(name)).to be_a(klass)
        end
      end

      it "hands out whatever adapters.#{name} the container holds" do
        fake = Object.new
        OpenLanes::Container.stub("adapters.#{name}", fake)

        expect(described_class.for(name)).to be(fake)
      end
    end
  end

  describe ".known?" do
    it "answers from the list of names, defaulting to claude" do
      expect([nil, "claude", :gemini, "gpt"].map { |n| described_class.known?(n) }).to eq([true, true, true, false])
    end
  end

  describe ".effort?" do
    it "accepts the five levels and nothing else" do
      expect(%w[low medium high xhigh max huge].map { |e| described_class.effort?(e) })
        .to eq([true, true, true, true, true, false])
    end
  end
end
