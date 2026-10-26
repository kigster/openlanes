# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::Title do
  subject(:title) { described_class.new(role: "supervisor", root: "/work/myproj", setter: ->(text) { set << text }) }

  let(:set) { [] }

  it("names the role and the project") { expect(title.set).to eq("openlanes-supervisor [myproj]") }

  it("adds the live status") { expect(title.set("up 2h, 1 restart")).to eq("openlanes-supervisor [myproj] up 2h, 1 restart") }

  it "sets the process title" do
    title.set("up 1m")
    expect(set).to eq(["openlanes-supervisor [myproj] up 1m"])
  end

  describe ".duration" do
    {
      45 => "45s", 60 => "1m", 3599 => "59m", 7200 => "2h", 86_400 => "1d", 300_000 => "3d"
    }.each do |seconds, text|
      it("reads #{seconds}s as #{text}") { expect(described_class.duration(seconds)).to eq(text) }
    end
  end
end
