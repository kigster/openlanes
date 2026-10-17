# frozen_string_literal: true

# M2 on a CLI read by shape (codex, pi).
RSpec.describe OpenLanes::Adapters::Stream do
  subject(:stream) { described_class.new }

  let(:decision) { OpenLanes::Plans::Journal.line("decision", "Integer cents") }

  def feed(*events) = events.each { stream.push("#{JSON.generate(it)}\n") }

  it "reads journal lines out of what a codex agent says" do
    feed({ type: "item.completed", item: { type: "agent_message", text: "Plan:\n#{decision}" } })
    expect(stream.progress.journal.map(&:text)).to eq(["Integer cents"])
  end

  it "takes a line once when the CLI repeats the message it closed" do
    feed({ type: "message_update", delta: { text: decision } },
      { type: "message_end", message: { content: [{ type: "text", text: decision }] } },
      { type: "agent_end", messages: [{ content: [{ type: "text", text: decision }] }] })
    expect(stream.journal.size).to eq(1)
  end
end
