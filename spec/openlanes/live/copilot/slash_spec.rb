# frozen_string_literal: true

# The copilot's three slash commands (plan 020.00): what the person types,
# read into a command for the engine, or into the usage that says why not.
RSpec.describe OpenLanes::Live::Copilot::Slash do
  def parse(text) = described_class.parse(text, id: "01JSLASH")

  it "leaves plain text to the copilot" do
    expect([parse("why has 020 not moved?"), parse(" /stop 20 is what I would type")]).to eq([nil, nil])
  end

  {
    "/stop 20"          => ["stop_plan", "020.00", {}],
    "/stop 020.00"      => ["stop_plan", "020.00", {}],
    "/restart 7.01"     => ["restart_plan", "007.01", {}],
    "/RESTART 007"      => ["restart_plan", "007.00", {}],
    "/concurrency 3"    => ["set_concurrency", nil, { "limit" => 3 }],
    "/concurrency  12 " => ["set_concurrency", nil, { "limit" => 12 }]
  }.each do |text, (kind, plan, payload)|
    it "reads #{text.inspect} as #{kind}, marked as the copilot's" do
      command = parse(text)
      expect(command).to have_attributes(id: "01JSLASH",
        kind:,
        plan:,
        agent: nil,
        payload: payload.merge("source" => "copilot"))
    end
  end

  it "builds a command the engine's gate takes" do
    expect { OpenLanes::Live::Command.check(parse("/concurrency 2")) }.not_to raise_error
  end

  {
    "/frobnicate"      => "/frobnicate is not one of them",
    "/"                => "/ is not one of them",
    "/stop"            => "/stop needs a plan number",
    "/stop twenty"     => "/stop needs a plan number",
    "/restart 20 21"   => "/restart needs a plan number",
    "/concurrency x"   => "/concurrency needs a whole number of at least 1",
    "/concurrency 0"   => "/concurrency needs a whole number of at least 1",
    "/concurrency 1.5" => "/concurrency needs a whole number of at least 1"
  }.each do |text, why|
    it "answers #{text.inspect} with the usage and why" do
      help = parse(text)
      expect(help).to be_a(described_class::Help)
      expect(help.text).to start_with("Slash commands:").and include("/stop NNN", "/restart NNN", "/concurrency N", why)
    end
  end
end
