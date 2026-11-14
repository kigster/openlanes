# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Start::Jobs, :tree do
  subject(:jobs) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  let(:task) { job_for(plan, coder).task }
  let(:job) { jobs.build(task, OpenLanes::Execution::Executor::Handle.new, from: :building, state: :building) }

  it "keys a job by plan and agent, with nothing counted yet" do
    expect([job.key, job.up, job.down, job.frame]).to eq(["001.00/#{coder.name}", 0, 0, 0])
  end

  it "records no restarts without a state file" do
    expect(jobs.handle("001.00", coder, 1).on_restart).to be_nil
  end

  it "copies a rebase's progress onto the job" do
    progress = Struct.new(:up, :down, :message, :activity).new(3, 4, "resolving", nil)
    jobs.rebase_progress_of(job).call(progress)
    expect([job.up, job.down, job.message]).to eq([3, 4, "rebasing: resolving"])
  end
end
