# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Dispatcher::Desk::Rounds do
  subject(:rounds) { described_class.new(registers) }

  let(:registers) { OpenLanes::Engine::Dispatcher::Desk::Registers.fresh }

  it "keeps one entry per round, the outcome overwriting the Started" do
    rounds.remember("001.00", "coder", :building, "Started", 1)
    rounds.remember("001.00", "coder", :building, "Completed", 1)
    expect(registers.history[%w[001.00 coder]]).to eq([{ state: :building, status: "Completed", round: 1 }])
  end

  it "hands back only an interrupted round" do
    rounds.remember("001.00", "coder", :building, "Interrupted", 1)
    expect([rounds.resume("001.00", "coder"), rounds.resume("001.00", "coder")]).to eq([true, false])
  end

  it "builds fresh registers that no two desks share" do
    other = OpenLanes::Engine::Dispatcher::Desk::Registers.fresh
    registers.running << :job
    expect(other.running).to be_empty
  end

  it "defaults every optional setup field" do
    setup = OpenLanes::Engine::Dispatcher::Desk::Setup.new(runner: :runner)
    expect([setup.state, setup.rounds, setup.stay, setup.budget]).to eq([nil, nil, false, nil])
  end
end
