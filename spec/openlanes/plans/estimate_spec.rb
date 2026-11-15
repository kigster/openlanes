# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::Estimate do
  it "reads a bare number as minutes" do
    expect([described_class.seconds("20"), described_class.seconds(20), described_class.seconds("1.5")]).to eq([1200, 1200, 90])
  end

  it "reads seconds, minutes and hours as written" do
    read = ["90s", "20m", "20 minutes", "1h", "1.5 hours", " 45 MIN "].map { described_class.seconds(it) }
    expect(read).to eq([90, 1200, 1200, 3600, 5400, 2700])
  end

  it "guesses at nothing else" do
    read = [nil, "", "about half an hour", "0", "-5", "20 fortnights", "0.001s"].map { described_class.seconds(it) }
    expect(read).to all(be_nil)
  end
end
