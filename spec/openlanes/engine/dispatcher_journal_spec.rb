# frozen_string_literal: true

require_relative "../live/live_context"

# M2: the dispatcher is the journal's one writer. It writes what the stream
# printed on every poll, only what it has not written yet, and once more
# when the round settles, so an agent killed mid-round keeps every entry.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  # The held executor, killed at the end rather than finishing.
  let(:executor) do
    Class.new(HeldExecutor) {
      def call(...)
        super
        OpenLanes::Execution::Executor::Result.new(ok: false,
          note: "timed out",
          up: 0,
          down: 0,
          subagents: 0,
          delegated: 0,
          seconds: 0.0,
          killed: :timeout)
      end
    }.new(traces)
  end
  let(:job) { dispatcher.running.first }
  let(:printed) { [] }
  let(:journal) { OpenLanes::Plans::PlanState.for(path_of("001.00")).journal("luke-backend", 1) }

  def entry(kind, text) = OpenLanes::Plans::Journal::Entry.new(kind:, text:)

  before do
    building("001.00", "tax-rule-dsl")
    start_agents
    allow(job.handle).to receive(:journal) { printed.dup }
  end

  it "writes each entry once, in order, across polls and the kill" do
    printed << entry("todo", "U1")
    2.times { dispatcher.tick }
    printed << entry("decision", "Redis")
    killed = job
    executor.release_all
    killed.thread.join(2)
    dispatcher.tick

    expect(journal.map { it.values_at("number", "kind", "text") }).to eq([[1, "todo", "U1"], [2, "decision", "Redis"]])
  end
end
