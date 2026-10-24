# frozen_string_literal: true

RSpec.describe OpenLanes::Arbitration::Appeal do
  it "reads the finding and the reason" do
    expect(described_class.parse("appeal: F2 because the spec rules that test out"))
      .to eq(described_class.new(finding: "F2", reason: "the spec rules that test out"))
  end

  it "accepts a lower-case id" do
    expect(described_class.parse("Appeal: f12 because cosmetic")&.finding).to eq("F12")
  end

  ["done", "appeal: F2", "appeal: because nothing", "appeal F2 because x", "appeal: X2 because y", nil].each do |note|
    it "is nil for #{note.inspect}" do
      expect(described_class.parse(note)).to be_nil
    end
  end
end
