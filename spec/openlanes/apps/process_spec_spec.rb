# frozen_string_literal: true

RSpec.describe OpenLanes::Apps::ProcessSpec do
  it "names its port variable from its name, upcased, anything else as _" do
    expect(described_class.new(name: "api-v2.x", start: "x").port_env).to eq("PORT_API_V2_X")
  end

  it "defaults to no readiness path, no globs and not previewed" do
    expect(described_class.new(name: "a", start: "x")).to have_attributes(ready: nil, restart_on: [], preview?: false)
  end
end
