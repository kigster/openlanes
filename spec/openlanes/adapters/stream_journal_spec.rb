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

  it "keeps a line said again in a later message, which the agent meant twice" do
    todo = OpenLanes::Plans::Journal.line("todo", "U1")
    done = OpenLanes::Plans::Journal.line("done", "U1")
    feed({ type: "item.completed", item: { id: "m1", type: "agent_message", text: todo } },
      { type: "item.completed", item: { id: "m2", type: "agent_message", text: done } },
      { type: "item.completed", item: { id: "m3", type: "agent_message", text: todo } })
    expect(stream.journal.map(&:kind)).to eq(%w[todo done todo])
  end

  it "keeps a line said again in later messages that carry no id" do
    todo = OpenLanes::Plans::Journal.line("todo", "U1")
    done = OpenLanes::Plans::Journal.line("done", "U1")
    closing = [todo, done, todo].map { { type: "message_end", message: { content: [{ type: "text", text: it }] } } }
    feed(*closing, { type: "agent_end", messages: closing.map { it[:message] } })
    expect(stream.journal.map(&:kind)).to eq(%w[todo done todo])
  end

  it "reads a message whose words are at the top of the event" do
    feed({ type: "message", content: [{ type: "text", text: "Plan:\n#{decision}" }] })
    expect(stream.journal.map(&:text)).to eq(["Integer cents"])
  end

  context "when the agent is killed before the message closes" do
    it "keeps a finished line from an update carrying the message so far" do
      feed({ type: "message_update", message: { role: "assistant", content: [{ type: "text", text: "#{decision}\nNext" }] } })
      expect(stream.progress.journal.map(&:text)).to eq(["Integer cents"])
    end

    it "keeps a finished line pieced together from deltas, and not the unfinished one" do
      half = OpenLanes::Plans::Journal.line("done", "U1")
      feed({ type: "message_update", assistantMessageEvent: { type: "text_delta", delta: decision[0, 10] } },
        { type: "message_update", assistantMessageEvent: { type: "text_delta", delta: "#{decision[10..]}\n#{half[0, 12]}" } })
      expect(stream.journal.map(&:text)).to eq(["Integer cents"])
    end
  end

  it "takes a line once when it was read from an update and the message then closes" do
    feed({ type: "message_update", delta: { text: "#{decision}\n" } },
      { type: "message_end", message: { content: [{ type: "text", text: "#{decision}\nDone." }] } },
      { type: "turn_end", message: { content: [{ type: "text", text: "#{decision}\nDone." }] } })
    expect(stream.journal.size).to eq(1)
  end

  it "reads every text block of a message, not only the first" do
    feed({ type: "message_end",
           message: { role: "assistant", content: [{ type: "text", text: "Working." }, { type: "text", text: decision }] } })
    expect(stream.journal.map(&:text)).to eq(["Integer cents"])
  end

  it "takes nothing from a tool's output" do
    feed({ type: "tool_execution_end", result: { content: [{ type: "text", text: decision }] } },
      { type: "message_end", message: { role: "toolResult", content: [{ type: "text", text: decision }] } },
      { type: "item.completed", item: { type: "command_execution", aggregated_output: decision, text: decision } })
    expect(stream.journal).to be_empty
  end

  it "takes nothing from the prompt it was given, which shows example lines" do
    feed({ type: "agent_end", messages: [{ role: "user", content: [{ type: "text", text: decision }] }] })
    expect(stream.journal).to be_empty
  end

  it "takes nothing from a tool call's input" do
    feed({ type: "message_end",
           message: { role: "assistant", content: [{ type: "toolCall", arguments: { text: decision } }] } })
    expect(stream.journal).to be_empty
  end

  it "still shows the first thing said as the activity" do
    feed({ type: "item.completed", item: { type: "agent_message", text: "Reading the spec" } })
    expect(stream.activity).to eq("Reading the spec")
  end
end
