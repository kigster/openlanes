# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Desk, :tree do
  include_context "with a dispatcher desk"

  let(:job) { job_for(plan, coder) }

  it "keeps one entry a round: the outcome overwrites the Started it was dispatched with" do
    desk.remember("001.00", coder.name, :building, "Started", 1)
    desk.remember("001.00", coder.name, :building, "Completed", 1)
    expect(desk.history[["001.00", coder.name]]).to eq([{ state: :building, status: "Completed", round: 1 }])
  end

  it "hands a requeued round back, and reopens the plan" do
    desk.remember("001.00", coder.name, :building, "Interrupted", 1)
    desk.finished_plans << "001.00"
    desk.forget_round(job)
    expect([desk.history[["001.00", coder.name]], desk.finished_plans]).to eq([[], []])
  end

  it "resumes only an interrupted round" do
    desk.remember("001.00", coder.name, :building, "Completed", 1)
    desk.remember("001.00", coder.name, :building, "Interrupted", 2)
    expect([desk.resume("001.00", coder.name), desk.resume("001.00", coder.name)]).to eq([true, false])
  end

  it "counts a plan with a running agent, or one being discarded, as untouchable" do
    building("002.00", "second")
    desk.running << job
    desk.discarding["002.00"] = OpenLanes::Engine::Dispatcher::Discard.new(ordinal: "002.00")
    expect(desk.untouchable).to contain_exactly("001.00", "002.00")
  end

  it "is quiet only with nothing running, draining or being thrown back" do
    quiet = desk.quiet?
    desk.running << job
    expect([quiet, desk.quiet?]).to eq([true, false])
  end

  it "lets --rounds tighten an agent's rounds, never loosen them" do
    tight = described_class.new(runner:, state: nil, rounds: 1, clock: OpenLanes::Clock::System, stay: false, journal: nil, extensions: nil)
    expect([tight.rounds_for(coder), desk.rounds_for(coder)]).to eq([1, coder.rounds])
  end

  it "finds a running job by its key, and tells it nothing when it has no control file" do
    desk.running << job
    expect([desk.job("001.00/#{coder.name}"), desk.signal("001.00/#{coder.name}", "STOP")]).to eq([job, false])
  end

  it "asks for a rescan when woken" do
    desk.wake!
    expect(desk.wake).to be(true)
  end
end
