# frozen_string_literal: true

# M2 from the stream's side: journal lines are read out of what the agent
# says, and only out of that, and reach the dispatcher in every progress
# snapshot, in order.
RSpec.describe OpenLanes::Execution::Transcript do
  subject(:transcript) { described_class.new { |progress| seen << progress } }

  let(:seen) { [] }
  let(:decision) { OpenLanes::Plans::Journal.line("decision", "Integer cents") }
  let(:done) { OpenLanes::Plans::Journal.line("done", "U1") }

  def assistant(*blocks, parent: nil)
    "#{JSON.generate(type: "assistant", parent_tool_use_id: parent, message: { content: blocks })}\n"
  end

  def kinds = transcript.journal.map(&:kind)

  it "reads the agent's journal lines out of its text, in order" do
    transcript.push(assistant({ type: "text", text: "Starting.\n#{decision}" }))
    transcript.push(assistant({ type: "text", text: done }))
    expect(kinds).to eq(%w[decision done])
  end

  it "hands the whole journal so far to every snapshot" do
    transcript.push(assistant({ type: "text", text: decision }))
    expect(seen.last.journal.map(&:kind)).to eq(["decision"])
  end

  it "hands over a new line even when the agent's phrase has not changed" do
    transcript.push(assistant({ type: "text", text: "Same start.\n#{decision}" }))
    transcript.push(assistant({ type: "text", text: "Same start.\n#{done}" }))
    expect(seen.last.journal.map(&:kind)).to eq(%w[decision done])
  end

  it "publishes nothing extra for a message with no journal line and the same phrase" do
    2.times { transcript.push(assistant({ type: "text", text: "Same start." })) }
    expect(seen.size).to eq(1)
  end

  it "ignores a line inside a tool's input, such as a file being written" do
    transcript.push(assistant({ type: "tool_use", name: "Write", input: { file_path: "x.md", content: decision } }))
    expect(kinds).to eq([])
  end

  it "ignores a sub-agent's text" do
    transcript.push(assistant({ type: "text", text: decision }, parent: "toolu_1"))
    expect(kinds).to eq([])
  end

  it "keeps a broken line as a rejection, for the dispatcher to report" do
    transcript.push(assistant({ type: "text", text: '{"openlanes_memory": {"kind": "wish", "text": "x"}}' }))
    expect(transcript.journal.map(&:class)).to eq([OpenLanes::Plans::Journal::Rejection])
  end
end
