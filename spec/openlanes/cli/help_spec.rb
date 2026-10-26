# frozen_string_literal: true

require "open3"

# The screen a new user reads first, so the order is the point: the two
# commands most days need, then the headless ones, then reference.
RSpec::Matchers.define_negated_matcher :not_match, :match

RSpec.describe "openlanes --help" do
  subject(:screen) do
    out, err, = Open3.capture3({ "NO_COLOR" => "1" }, File.expand_path("../../../exe/openlanes", __dir__), "--help")
    out + err
  end

  it "opens with the web operation, then the headless commands, then reference" do
    positions = ["OPENLANES DEFAULT WEB OPERATION", "HEADLESS OPERATION", "REFERENCE"].map { screen.index(it) }
    expect([positions.none?(nil), positions.compact == positions.compact.sort]).to eq([true, true])
  end

  it "lists setup, init, start, stop and status under the web operation, and run under headless" do
    web = screen[/OPENLANES DEFAULT WEB OPERATION\n(.*?)\n\n/m, 1]
    headless = screen[/HEADLESS OPERATION\n(.*?)\n\n/m, 1]
    expect([web.scan(/^  (\w[\w-]*)/).flatten, headless]).to match([%w[setup init start stop status], include("  run ")])
  end

  # Spawned by start, never typed (C5), so the screen does not offer it.
  it "does not list web" do
    expect(screen).not_to match(/^  web\b/)
  end

  # Spawned by start's supervisor and by mprocs (S1).
  it "does not list engine" do
    expect(screen).not_to match(/^  engine\b/)
  end

  it "lists plans and project, and no longer list-plans or app" do
    expect(screen).to match(/^  plans /).and match(/^  project, preview /).and(not_match(/^  (list-plans|app)\b/))
  end

  it "says that start is the factory, and run works the plans named" do
    expect(screen).to include("The factory: the engine and its control room", "openlanes run 005,006")
  end

  it "lists review under headless operation" do
    headless = screen[/HEADLESS OPERATION\n(.*?)\n\n/m, 1]
    expect(headless).to include("  review ")
  end
end
