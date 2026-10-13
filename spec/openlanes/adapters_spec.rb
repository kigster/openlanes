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
  end

  describe ".effort?" do
    it "accepts the five levels and nothing else" do
      expect(%w[low medium high xhigh max huge].map { |e| described_class.effort?(e) })
        .to eq([true, true, true, true, true, false])
    end
  end
end
