# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenLanes::Agents::Agent do
  base = { name: "x", description: "", handles: [], advances_to: nil, model: nil, allowed_tools: [], may: [],
           network: false, timeout: nil, prompt: "", path: "x.md" }.freeze

  define_method(:agent) { |**overrides| described_class.new(**base, **overrides) }

  it "defaults to review stage 1, watching nothing" do
    expect([agent.review_stage, agent.watches]).to eq([1, []])
  end

  it "keeps the review stage and the globs it is given" do
    expect([agent(review_stage: 2, watches: ["lib/**"]).review_stage, agent(watches: ["lib/**"]).watches]).to eq([2, ["lib/**"]])
  end

  describe "#watching?" do
    it "watches every diff when it names no globs" do
      expect(agent.watching?(["README.md"])).to be(true)
    end

    it "watches a diff that touches a file under one of its globs, however deep" do
      expect(agent(watches: ["lib/**", "web/src/**"]).watching?(["README.md", "lib/openlanes/a/b.rb"])).to be(true)
    end

    it "skips a diff that touches none of its globs" do
      expect(agent(watches: ["lib/**"]).watching?(["README.md", "spec/a_spec.rb"])).to be(false)
    end

    it "skips an empty diff when it names globs" do
      expect(agent(watches: ["lib/**"]).watching?([])).to be(false)
    end
  end
end
