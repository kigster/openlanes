# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Poll::Sighting, :tree do
  subject(:sighting) { described_class.new(desk, journal:) }

  include_context "with a dispatcher desk"

  let(:journal) { instance_double(OpenLanes::Engine::Dispatcher::Poll::Journal, call: nil) }
  let(:handle) { OpenLanes::Execution::Executor::Handle.new }
  let(:job) { job_for(plan, coder, handle:, up: 0, down: 0, file: "plan.md") }

  it "keeps the file a job had when its agent has signed nothing yet" do
    sighting.call(job)
    expect([job.file, job.status]).to eq(["plan.md", nil])
  end

  it "hands the job's journal lines on to be written" do
    sighting.call(job)
    expect(journal).to have_received(:call).with(job)
  end
end
