# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Sessions do
  subject(:sessions) { described_class.new }

  let(:entry) { ->(text) { OpenLanes::Plans::Journal::Entry.new(kind: "note", text:) } }

  # A compacted round's continuation is a second transcript; the journal the
  # dispatcher counts must not start again at it.
  it "puts the journal of the sessions already over before the running one's" do
    first = OpenLanes::Execution::Transcript.new
    first.push("#{JSON.generate(type: "assistant", message: { content: [{ type: "text", text: OpenLanes::Plans::Journal.line("note", "a") }] })}\n")
    sessions << first << OpenLanes::Execution::Transcript.new
    progress = OpenLanes::Execution::Transcript::Progress.new(activity: nil, up: 0, down: 0, subagents: 0, journal: [entry.call("b")])
    expect(sessions.carry(progress).journal.map(&:text)).to eq(%w[a b])
  end
end
