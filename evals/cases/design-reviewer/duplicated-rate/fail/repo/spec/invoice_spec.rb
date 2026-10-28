require_relative "../lib/invoice"

RSpec.describe Invoice do
  it "adds sales tax" do
    expect(described_class.new(10_000).total).to eq(10_825)
  end
end
