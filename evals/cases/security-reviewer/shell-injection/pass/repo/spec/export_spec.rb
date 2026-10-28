require_relative "../lib/export"

RSpec.describe Export do
  it "archives data/ under the given name" do
    export = described_class.new
    allow(export).to receive(:system).and_return(true)
    export.call("orders")
    expect(export).to have_received(:system).with("tar -czf exports/orders.tgz data/")
  end
end
