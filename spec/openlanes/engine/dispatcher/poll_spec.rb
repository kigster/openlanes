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

  describe "#ask_for_time" do
    let(:handle) do
      OpenLanes::Execution::Executor::Handle.new.tap do |made|
        made.clock = OpenLanes::Execution::Clock.new(seconds: left, control: File.join(Dir.mktmpdir, "control"), on_expire: -> {})
      end
    end
    let(:left) { OpenLanes::Engine::Extensions::ASK_AT }
    let(:state) { OpenLanes::Plans::PlanState.for(plan.feature.path) }

    before do
      allow(OpenLanes::UI).to receive(:log)
      allow(desk.feed).to receive(:append)
      desk.running << job
    end

    it "gives an agent near the end of its clock more time, and journals it" do
      poll.ask_for_time
      aggregate_failures do
        expect(state.extensions).to contain_exactly(include("by" => "auto", "grant" => "live", "seconds" => coder.extension_cap))
        expect(handle.remaining).to be_within(2).of(left + coder.extension_cap)
        expect(desk.feed).to have_received(:append).with(:extension, plan: "001.00", agent: "backend-coder", seconds: coder.extension_cap)
      end
    end

    context "with time to spare" do
      let(:left) { OpenLanes::Engine::Extensions::ASK_AT + 60 }

      it "reads nothing and grants nothing" do
        poll.ask_for_time
        aggregate_failures do
          expect(state.extensions).to eq([])
          expect(desk.feed).not_to have_received(:append)
        end
      end
    end

    it "changes nothing under a dry run" do
      allow(runner).to receive(:dry_run?).and_return(true)
      poll.ask_for_time
      expect([state.extensions, handle.remaining]).to match([[], be_within(2).of(left)])
    end
  end

  it "writes no journal for a job that printed none" do
    expect(poll.record_journal(job)).to be_nil
  end
end
