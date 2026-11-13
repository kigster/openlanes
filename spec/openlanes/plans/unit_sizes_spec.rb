# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::UnitSizes do
  let(:plan) do
    <<~MD
      ## Backend

      ### B1 Packet

      - **Discipline:** back end
      - **Size:** small

      ### B5a Split dispatcher

      - **Size:** Large
      - **Size:** small

      ### B3 Sizing

      - **Owns:** profile.rb

      ## Frontend

      - **Size:** medium

      ### F1 Board

      - **Size:** enormous
    MD
  end

  it "reads each unit's first size, case forgiven" do
    expect(described_class.parse(plan)).to eq("B1" => "small", "B5a" => "large")
  end

  it "ignores a size outside any unit and a word that is not a size" do
    expect(described_class.parse(plan)).not_to include("F1")
  end

  it "answers the largest size" do
    expect(described_class.largest(plan)).to eq("large")
  end

  it "answers nil for a plan with no sized unit, or no plan at all" do
    expect([described_class.largest("### B1 X\n\n- **Owns:** a\n"), described_class.largest(nil)]).to eq([nil, nil])
  end
end
