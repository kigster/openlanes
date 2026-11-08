require_relative "../lib/ledger"

RSpec.describe Ledger do
  it "writes a line" do
    path = File.join(Dir.mktmpdir, "ledger.log")
    described_class.new(path).append("one")
    expect(File.read(path)).to eq("one\n")
  end
end
