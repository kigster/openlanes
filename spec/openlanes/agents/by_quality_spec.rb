# frozen_string_literal: true

RSpec.describe OpenLanes::Agents::ByQuality do
  it "refuses a quality that does not exist, a non-mapping and a bad effort" do
    aggregate_failures do
      expect { described_class.parse({ "ultra" => { "model" => "fable" } }, "a.md") }.to raise_error(OpenLanes::Error, /"ultra" is not one of/)
      expect { described_class.parse("fable", "a.md") }.to raise_error(OpenLanes::Error, /must be a mapping/)
      expect { described_class.parse({ "high" => "fable" }, "a.md") }.to raise_error(OpenLanes::Error, /values must be mappings/)
      expect { described_class.parse({ "high" => { "effort" => "huge" } }, "a.md") }.to raise_error(OpenLanes::Error, /effort "huge"/)
    end
  end

  it "reads the shipped staff-reviewer's high-quality model" do
    agent = OpenLanes::Agents::Registry.new.find("staff-reviewer")
    expect(agent.by_quality.for(:high)).to eq(model: "fable", effort: "high")
  end
end
