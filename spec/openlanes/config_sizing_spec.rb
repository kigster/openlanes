# frozen_string_literal: true

RSpec.describe OpenLanes::Config, "#sizing" do
  def parse(yaml) = described_class.parse(yaml, path: ".openlanes.yml")

  it "defaults small, medium and large when the file says nothing" do
    expect(parse("jobs: 2\n").sizing.table).to eq(OpenLanes::Agents::Sizing::DEFAULTS)
  end

  it "maps each size to its default profile" do
    sizing = described_class.new.sizing
    expected = [{ model: "sonnet", effort: "medium" }, { model: "opus", effort: "medium" }, { model: "opus", effort: "high" }]
    expect(%w[small medium large].map { sizing.for(it) }).to eq(expected)
  end

  it "overrides one key of one size and keeps the rest" do
    sizing = parse("sizing:\n  large: { model: fable }\n").sizing
    expect([sizing.for("large"), sizing.for("small")]).to eq([{ model: "fable", effort: "high" }, { model: "sonnet", effort: "medium" }])
  end

  it "lifts the ceiling only for a size the file changed" do
    sizing = parse("sizing:\n  large: { model: fable }\n").sizing
    expect([sizing.uncapped?("large"), sizing.uncapped?("small"), sizing.uncapped?(nil)]).to eq([true, false, false])
  end

  it "answers nil for no size" do
    expect(described_class.new.sizing.for(nil)).to be_nil
  end

  it "refuses an unknown size" do
    expect { parse("sizing:\n  huge: { model: opus }\n") }.to raise_error(OpenLanes::Error, /unknown size huge/)
  end

  it "refuses an unknown key" do
    expect { parse("sizing:\n  large: { temperature: 1 }\n") }.to raise_error(OpenLanes::Error, /unknown key temperature/)
  end

  it "refuses an effort no adapter knows" do
    expect { parse("sizing:\n  small: { effort: lazy }\n") }.to raise_error(OpenLanes::Error, /effort: lazy/)
  end

  it "refuses a section that is not a mapping, and an entry that is not one" do
    expect { parse("sizing: [large]\n") }.to raise_error(OpenLanes::Error, /must be a mapping/)
    expect { parse("sizing:\n  large: opus\n") }.to raise_error(OpenLanes::Error, /sizing.large: must be a mapping/)
  end
end
