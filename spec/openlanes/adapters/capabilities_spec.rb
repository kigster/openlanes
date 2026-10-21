# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Capabilities do
  OpenLanes::Adapters.registry.each do |name, klass|
    context "with the #{name} adapter" do
      subject(:adapter) { klass.new }

      it "declares its capabilities itself rather than inheriting them" do
        expect(klass.instance_method(:capabilities).owner).to eq(klass)
      end

      it "declares every capability field" do
        expect(adapter.capabilities.to_h.keys).to eq(described_class.members)
      end

      it "answers each predicate from that one value" do
        caps = adapter.capabilities
        expect([adapter.compacts?, adapter.resumes?, adapter.enforces_tool_denial?, adapter.compact_prompt])
          .to eq([caps.compacts, caps.resumes, caps.enforces_tool_denial, caps.compact_prompt])
      end

      it "is frozen" do
        expect(adapter.capabilities).to be_frozen
      end
    end
  end

  it "makes Base#capabilities abstract" do
    expect { OpenLanes::Adapters::Base.new.capabilities }.to raise_error(NotImplementedError, /capabilities/)
  end

  it "refuses a compact prompt without compaction" do
    expect { described_class.new(compacts: false, resumes: true, enforces_tool_denial: true, compact_prompt: "/c") }
      .to raise_error(ArgumentError, /exactly when compacts/)
  end

  it "refuses compaction without a compact prompt" do
    expect { described_class.new(compacts: true, resumes: true, enforces_tool_denial: true, compact_prompt: nil) }
      .to raise_error(ArgumentError, /exactly when compacts/)
  end

  describe "OpenLanes::Adapters.lean_flags" do
    it "gives claude's lean flags without the caller naming the class" do
      expect(OpenLanes::Adapters.lean_flags("claude")).to eq(OpenLanes::Adapters::Claude::LEAN)
    end

    it "is empty for an adapter that builds its own" do
      expect(OpenLanes::Adapters.lean_flags("codex")).to eq([])
    end
  end
end
