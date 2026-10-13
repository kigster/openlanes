# frozen_string_literal: true

RSpec.describe OpenLanes::UI do
  let(:heard) { [] }
  let!(:tap) { described_class.tap_log(->(message, fields) { heard << [message, fields] }) }

  after { described_class.log_taps.each { described_class.untap_log(it) } }

  it "hands every logged line to its taps, with no log file set" do
    described_class.log("started", plan: "001.00")
    expect(heard).to eq([["started", { plan: "001.00" }]])
  end

  it "stops once untapped" do
    described_class.untap_log(tap)
    described_class.log("unheard")
    expect(heard).to eq([])
  end
end
