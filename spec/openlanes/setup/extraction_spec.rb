# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::Extraction do
  it "finds a route from the environment it is given" do
    expect(described_class.route({ "OPENAI_API_KEY" => "not-a-real-key" }).label).to include("OPENAI_API_KEY")
  end
end
