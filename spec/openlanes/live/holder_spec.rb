# frozen_string_literal: true

RSpec.describe OpenLanes::Live::Holder do
  subject(:holder) { described_class.parse(name) }

  let(:me) { OpenLanes::Live::Node.new(id: "m1", user: "dana", host: "studio-mini", ip: nil, checkout: "~/src", checkout_id: "c1") }

  describe "a run on this machine" do
    let(:name) { "m1:c1:run-4242" }

    it { expect(holder.run_pid).to eq(4242) }
    it { expect(holder.describe(from: me)).to eq("openlanes run (pid 4242) on this machine") }
  end

  describe "this checkout's factory" do
    let(:name) { "m1:c1" }

    it { expect(holder.run_pid).to be_nil }
    it { expect(holder.describe(from: me)).to eq("this checkout's factory (openlanes start)") }
  end

  describe "a factory in another checkout" do
    let(:name) { "m1:c9" }

    it { expect(holder.describe(from: me)).to eq("the factory on this machine") }
  end

  describe "a run on another machine" do
    let(:name) { "m2:c1:run-7" }

    it { expect(holder.describe(from: me)).to eq("openlanes run (pid 7) on another machine") }
  end

  describe "a role that is no run" do
    let(:name) { "m1:c1:run-x" }

    it { expect(holder.run_pid).to be_nil }
  end
end
