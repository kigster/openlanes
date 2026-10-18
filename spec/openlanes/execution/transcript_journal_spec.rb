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

  context "with --include-partial-messages" do
    def streamed(inner, parent: nil) = "#{JSON.generate(type: "stream_event", parent_tool_use_id: parent, event: inner)}\n"

    def delta(text, index: 0, type: "text_delta", parent: nil)
      key = type == "text_delta" ? :text : :partial_json
      streamed({ type: "content_block_delta", index:, delta: { type:, key => text } }, parent:)
    end

    before { transcript.push(streamed({ type: "content_block_start", index: 0, content_block: { type: "text" } })) }

    it "keeps a finished line when the agent is killed before the message arrives" do
      transcript.push(delta(decision[0, 9]))
      transcript.push(delta("#{decision[9..]}\n#{done[0, 8]}"))
      expect(seen.last.journal.map(&:kind)).to eq(["decision"])
    end

    it "does not take the line again when the message arrives" do
      transcript.push(delta("#{decision}\n"))
      transcript.push(assistant({ type: "text", text: "#{decision}\n#{done}" }))
      expect(kinds).to eq(%w[decision done])
    end

    it "ignores a sub-agent's deltas and a tool's input" do
      transcript.push(delta("#{decision}\n", parent: "toolu_1"))
      transcript.push(delta("#{decision}\n", index: 1, type: "input_json_delta"))
      expect(kinds).to eq([])
    end
  end
end
