# frozen_string_literal: true

require_relative "desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Poll, :tree do
  subject(:poll) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  let(:handle) { OpenLanes::Execution::Executor::Handle.new }
  let(:job) { job_for(plan, coder, handle:, up: 0, down: 0) }
  let(:mail) { instance_double(OpenLanes::Live::Mail) }

  it "reads nothing, and fails nothing, with nobody running and no mail" do
    expect([poll.poll, poll.drain_mail, poll.ask_for_time]).to eq([[], nil, []])
  end

  it "leaves a running job without a ledger line as it was" do
    desk.running << job
    poll.poll
    expect([job.status, job.file]).to eq([nil, nil])
  end

  it "drains every plan the stream has mail for, running or not" do
    desk.mail = mail
    allow(mail).to receive_messages(plans_since: [["001.00"], "5-0"], drain: [])
    poll.drain_mail
    expect(mail).to have_received(:drain).with(plan: "001.00", consumer: "harness")
  end

  it "loses the drain, never the tick, when Redis goes away" do
    desk.mail = mail
    allow(mail).to receive(:plans_since).and_raise(OpenLanes::Live::Unavailable, "redis is down")
    expect { poll.drain_mail }.not_to raise_error
  end

  it "writes no journal for a job that printed none" do
    expect(poll.record_journal(job)).to be_nil
  end
end
