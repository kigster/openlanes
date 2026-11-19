# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Drain do
  subject(:drain) { described_class.new(max_tokens: 100, fresh_budget: false) }

  let(:handle) { instance_double(OpenLanes::Execution::Executor::Handle, kill!: nil) }

  def sessions(sent, made) = instance_double(OpenLanes::Execution::Executor::Sessions, up: sent, down: made, fresh: sent + made)

  after { OpenLanes::Execution::Control.reset! }

  it "kills an agent over its budget" do
    drain.abort_if_over(sessions(90, 20), handle)
    expect(handle).to have_received(:kill!).with(grace: 0, reason: :budget)
  end

  it "leaves one inside it alone" do
    drain.abort_if_over(sessions(50, 20), handle)
    expect(handle).not_to have_received(:kill!)
  end

  it "reads every chunk into the running session, then finishes it" do
    transcript = instance_double(OpenLanes::Execution::Transcript, push: nil, finish: nil)
    running = instance_double(OpenLanes::Execution::Executor::Sessions, current: transcript, up: 0, down: 0, fresh: 0)
    child = instance_double(OpenLanes::Execution::Child, wait: :exited)
    allow(child).to receive(:each_chunk).and_yield("a").and_yield("b")
    drain.drain(child, running, handle)
    expect(transcript).to have_received(:push).twice
  end
end
