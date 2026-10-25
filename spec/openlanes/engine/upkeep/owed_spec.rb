# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Upkeep::Owed do
  subject(:owed) { described_class.new }

  let(:entry) { described_class::Entry.new(ordinal: "033.00", url: "https://github.com/example/repo/pull/1") }
  let(:conflict) { OpenLanes::Engine::Upkeep::Conflict.new(ordinal: "033.00", number: 1, url: entry.url) }

  it "owes an answer from every entry once main moves, and not again until it moves" do
    first = owed.moved!("main-1", [entry])
    owed.settle(entry)
    second = owed.moved!("main-1", [entry])

    expect([first, second, owed.due]).to eq([true, false, []])
  end

  it "leaves a busy plan owed for later" do
    owed.moved!("main-1", [entry])

    expect([owed.due(busy: ["033.00"]), owed.due]).to eq([[], [entry]])
  end

  it "owes an answer again after a recheck" do
    owed.moved!("main-1", [])
    owed.recheck(conflict)

    expect(owed.due).to eq([entry])
  end

  it "lets a clean rebase be pushed once per head of main" do
    owed.moved!("main-1", [])
    first = owed.pushable?(conflict)
    second = owed.pushable?(conflict)
    owed.moved!("main-2", [])

    expect([first, second, owed.pushable?(conflict)]).to eq([true, false, true])
  end
end
