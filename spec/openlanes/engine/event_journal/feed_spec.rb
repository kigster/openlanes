# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::EventJournal::Feed do
  subject(:feed) { described_class.new(journal) }

  let(:journal) { instance_double(OpenLanes::Engine::EventJournal, append: nil) }
  let(:trace) { File.join(Dir.mktmpdir, "trace.ndjson") }
  let(:handle) { instance_double(OpenLanes::Execution::Executor::Handle, pid: 42, session: nil, trace:) }
  let(:task) { instance_double(OpenLanes::Engine::Runner::Task, subject: plan, agent:, round: 1) }
  let(:plan) { instance_double(OpenLanes::Plans::Subject, feature: instance_double(OpenLanes::Plans::Feature, ordinal: "003.00")) }
  let(:agent) { instance_double(OpenLanes::Agents::Agent, name: "luke-backend") }
  let(:job) { OpenLanes::Engine::Dispatcher::Job.new(key: "003.00/luke-backend", task:, handle:) }
  let(:who) { { plan: "003.00", agent: "luke-backend" } }

  let(:spent) { { ordinal: "003.00", agent: "luke-backend", ok: true, up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0 } }

  def attempt(from, to, note) = OpenLanes::Engine::Runner::Attempt.new(**spent, from:, to:, note:)

  before { allow(OpenLanes::Execution::ProcessStart).to receive(:of).and_return(nil) }

  it "says an agent started once per pid, its session once named, and its trace each time it grows" do
    feed.progress(job)
    allow(handle).to receive(:session).and_return("s-1")
    File.write(trace, "x")
    2.times { feed.progress(job) }

    aggregate_failures do
      expect(journal).to have_received(:append).with(:agent_started, **who, round: 1, pid: 42, started_at: nil, session_id: nil, output_file: trace).once
      expect(journal).to have_received(:append).with(:agent_session, **who, session_id: "s-1").once
      expect(journal).to have_received(:append).with(:agent_offset, **who, offset: 1).once
    end
  end

  it "ends an agent it saw start, and names the event that moved the plan" do
    feed.progress(job)
    feed.ended(job, attempt(:planned, :building, "done"))

    aggregate_failures do
      expect(journal).to have_received(:append).with(:agent_ended, **who, exit: 0, note: "done")
      expect(journal).to have_received(:append).with(:transition, plan: "003.00", from: "planned", to: "building", event: anything)
    end
  end

  it "calls a move to an earlier state a step back" do
    feed.ended(job, attempt(:building, :planned, ""))

    expect(journal).to have_received(:append).with(:transition, plan: "003.00", from: "building", to: "planned", event: "step_back")
  end

  it "reports a journal it cannot write rather than raising" do
    allow(journal).to receive(:append).and_raise(Errno::ENOSPC)
    allow(OpenLanes::UI).to receive(:log)
    feed.append(:run_started)

    expect(OpenLanes::UI).to have_received(:log).with(/journal write failed: Errno::ENOSPC/, level: :warn)
  end

  it "does nothing without a journal" do
    expect([described_class.new(nil).progress(job), described_class.new(nil).append(:run_started)]).to eq([nil, nil])
  end
end
