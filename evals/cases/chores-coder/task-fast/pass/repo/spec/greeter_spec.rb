require_relative "../lib/greeter"

RSpec.describe Greeter do
  it "greets" do
    expect(described_class.greet("Ada")).to eq("Hello, Ada!")
  end
end
