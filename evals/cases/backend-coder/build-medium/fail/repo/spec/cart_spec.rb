require_relative "../lib/cart"

RSpec.describe Cart do
  it "adds a line" do
    expect(described_class.new.add("A1", 2)).to eq(2)
  end
end
