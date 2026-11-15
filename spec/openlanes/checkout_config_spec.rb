# frozen_string_literal: true

# Plan 056, B1: the suite must not read the developer's own .openlanes.yml.
RSpec.describe CheckoutConfig do
  it "reads the checkout's .openlanes.yml as empty" do
    expect(OpenLanes::Config.load(described_class::ROOT).file?).to be(false)
  end

  it "passes any other root through", :tree do
    root = File.dirname(plans_root)
    File.write(File.join(root, ".openlanes.yml"), "jobs: 3\n")
    expect(OpenLanes::Config.load(root).jobs).to eq(3)
  end

  it "reads the real file when the example opts in", :checkout_config do
    skip "the checkout has no .openlanes.yml" unless File.file?(File.join(described_class::ROOT, ".openlanes.yml"))
    expect(OpenLanes::Config.load(described_class::ROOT).file?).to be(true)
  end
end
