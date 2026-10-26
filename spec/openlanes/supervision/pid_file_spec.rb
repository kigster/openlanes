# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::PidFile do
  subject(:file) { described_class.new(role:, pid: 4242, started: "Mon Oct  5 01:21:45 2026", root: "/work/myproj", plans:) }

  let(:role) { "engine" }
  let(:plans) { [] }

  describe "#name" do
    it { expect(file.name).to eq("engine.pid") }

    context "when the role is run" do
      let(:role) { "run" }

      it("carries its pid") { expect(file.name).to eq("run-4242.pid") }
    end
  end

  describe "#title" do
    it { expect(file.title).to eq("openlanes-engine [myproj]") }
  end

  describe ".parse" do
    let(:plans) { %w[005 006] }

    it("reads back what #to_json wrote") { expect(described_class.parse(file.to_json)).to eq(file) }

    it("keeps the children given up on") do
      expect(described_class.parse(file.with(failed: { "web" => "3 crashes in 5m" }).to_json).failed).to eq("web" => "3 crashes in 5m")
    end

    it("reads nothing out of half a file") { expect(described_class.parse('{"role":')).to be_nil }

    it("reads nothing out of a file with no pid") { expect(described_class.parse('{"role":"web","root":"/x"}')).to be_nil }
  end

  describe "#uptime" do
    it { expect(file.uptime(now: Time.new(2026, 10, 5, 1, 22, 45))).to eq(60) }

    it("is unknown without a start time") { expect(file.with(started: nil).uptime).to be_nil }

    it("is unknown for a start time it cannot read") { expect(file.with(started: "yesterday").uptime).to be_nil }
  end
end
