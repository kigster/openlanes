# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Agents::Names do
  let(:defined) { OpenLanes::Agents.registry.all.map(&:name) }

  it "has a constant for every agent in agents/" do
    expect(defined - described_class.all).to be_empty
  end

  it "names no agent that has no definition, except the ones still planned" do
    expect(described_class.all - defined).to match_array(described_class::PLANNED)
  end

  it "spells each constant as its name, upcased" do
    described_class.constants.each do |constant|
      value = described_class.const_get(constant)
      expect(value.upcase.tr("-", "_")).to eq(constant.to_s) if value.is_a?(String)
    end
  end

  it "pairs the two coders as the builders" do
    expect(described_class::BUILDERS).to eq(%w[backend-coder frontend-coder])
  end
end
