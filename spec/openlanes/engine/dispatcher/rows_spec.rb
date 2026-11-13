# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Rows, :tree do
  subject(:rows) { described_class.new(desk, waiting_on: -> { { "001.00" => "PR #7" } }) }

  include_context "with a dispatcher desk"

  let(:row) { instance_double(OpenLanes::Engine::Board::Row, ordinal: "001.00") }

  it "shows an empty run as running nobody, with what a person owes" do
    board = rows.board
    expect([board.running, board.rows, board.waiting_on, board.status]).to eq([0, [], { "001.00" => "PR #7" }, :running])
  end

  it "keeps a settled row on the screen, then drops it once it has lingered" do
    desk.recent << { at: OpenLanes::UI.monotonic, row: }
    shown = rows.board.rows
    desk.recent.first[:at] -= OpenLanes::Engine::Dispatcher::LINGER + 1
    expect([shown, rows.board.rows]).to eq([[row], []])
  end

  it "says an idle, quiet run is idle" do
    desk.idle = true
    expect(rows.board.status).to eq(:idle)
  end
end
