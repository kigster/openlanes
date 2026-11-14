# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Poll::Journal, :tree do
  subject(:journal) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  let(:entry) { OpenLanes::Plans::Journal.scan('{"openlanes_memory":{"kind":"note","text":"kept"}}').first }
  let(:job) { job_for(plan, coder, journal: [entry]) }

  it "writes a printed entry into the plan's state.json and moves its place on" do
    journal.call(job)
    expect(job.journaled).to eq(1)
  end

  it "leaves the lines for the next tick when the folder cannot be found" do
    allow(desk).to receive(:fresh).and_return(nil)
    journal.call(job)
    expect(job.journaled.to_i).to eq(0)
  end

  it "writes nothing for a job resolving a rebase" do
    job.rebase = :stopped
    expect(journal.call(job)).to be_nil
  end
end
