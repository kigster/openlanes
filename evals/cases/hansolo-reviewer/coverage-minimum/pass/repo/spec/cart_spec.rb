require_relative "../lib/cart"

RSpec.describe Cart do
  it "sums the lines" do
    cart = described_class.new
    cart.add(250, 2)
    expect(cart.total).to eq(500)
  end
end
