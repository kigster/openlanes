# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Stream do
  subject(:stream) { described_class.new { |progress| seen << progress } }

  let(:seen) { [] }
  let(:lines) do
    [
      { type: "thread.started" },
      { type: "item.completed", item: { type: "agent_message", text: "Reading the migration" } },
      { type: "item.started", item: { type: "command_execution", command: "ls" } },
      { type: "tool_call", name: "bash" },
      { type: "turn.completed", usage: { input_tokens: 1200, cached_input_tokens: 800, output_tokens: 300 } }
    ].map { |e| "#{JSON.generate(e)}\n" }
  end

  before do
    lines.join.chars.each_slice(17) { |chunk| stream.push(chunk.join) }
    stream.push("not json at all\n")
    stream.finish
  end

  it "meters usage wherever it appears" do
    expect([stream.up, stream.down]).to eq([1200, 300])
  end

  it "keeps the cached input apart" do
    expect(stream).to have_attributes(cached: 800, fresh: 700)
  end

  it "counts tool calls by the shape of the event type" do
    expect(stream.tools).to eq(1)
  end

  it "keeps the last thing the agent said" do
    expect(stream.result).to eq("Reading the migration")
  end

  it "keeps lines that are not JSON" do
    expect(stream.plain).to eq(["not json at all"])
  end

  it "reports progress as it goes" do
    expect(seen.last).to be_a(OpenLanes::Execution::Transcript::Progress)
  end

  # codex and pi never say they delegated, so the page draws no sub-agent tiles for them.
  it "reports no sub-agents running" do
    expect(seen.last.running).to eq([])
  end

  it "is not failed when nothing failed" do
    expect(stream.failed?).to be(false)
  end

  context "when the CLI reports an error" do
    subject(:failing) { described_class.new }

    before do
      failing.push(%({"type":"error","message":"rate limited"}\n))
      failing.finish
    end

    it "carries the message" do
      expect([failing.failed?, failing.error]).to eq([true, "rate limited"])
    end
  end

  context "with a trace file" do
    subject(:traced) { described_class.new(trace: path) }

    let(:path) { File.join(Dir.mktmpdir, "trace.ndjson") }

    before do
      traced.push(%({"type":"x"}\n))
      traced.finish
    end

    it "keeps every line verbatim" do
      expect(File.read(path)).to eq(%({"type":"x"}\n))
    end
  end
end
