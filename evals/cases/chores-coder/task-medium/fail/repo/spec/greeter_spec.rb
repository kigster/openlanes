require_relative "../lib/greeter"

RSpec.describe Greeter do
  it "greets" do
    expect(described_class.greet("Ada")).to eq("Hello, Ada!")
  end

  it "shouts when asked" do
    expect(described_class.greet("Ada", shout: true)).to eq("HELLO, ADA!")
  end
end
