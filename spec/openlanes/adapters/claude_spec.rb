# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Claude do
  subject(:adapter) { described_class.new }

  let(:invocation) do
    OpenLanes::Adapters::Invocation.new(prompt: "do it",
      root: "/repo",
      model: "sonnet",
      effort: "high",
      allowed_tools: %w[Read Bash],
      denied_tools: ["WebFetch", "Bash(git push:*)"])
  end
  let(:argv) { adapter.argv(invocation) }

  it "streams JSON from claude -p" do
    expect(argv.first(3)).to eq(["claude", "-p", "do it"])
  end

  it "keeps the operator's plugins, skills, hooks and MCP servers out by default" do
    expect(argv).to include("--setting-sources", "project,local", "--strict-mcp-config", "--disable-slash-commands")
  end

  it "lets them back in when the invocation is not lean" do
    expect(adapter.argv(invocation.with(lean: false))).not_to include("--disable-slash-commands")
  end

  it "passes model, effort and the tool grants" do
    expect(argv.each_slice(1).to_a.flatten).to include("--model",
      "sonnet",
      "--effort",
      "high",
      "--allowedTools",
      "Read,Bash",
      "--disallowedTools",
      "WebFetch,Bash(git push:*)")
  end

  describe "#model" do
    it "runs anything above Opus as Opus" do
      expect(%w[fable claude-fable-5-1].map { |m| adapter.model(m) }).to eq(%w[opus opus])
    end

    it "leaves Opus and below alone" do
      expect(%w[haiku sonnet opus claude-opus-5-5].map { |m| adapter.model(m) })
        .to eq(%w[haiku sonnet opus claude-opus-5-5])
    end

    it "leaves a model it does not rank alone" do
      expect(adapter.model("something-else")).to eq("something-else")
    end
  end

  it "says the CLI enforces the denial" do
    expect(adapter.enforces_tool_denial?).to be(true)
  end

  it "reads the stream with the Claude transcript" do
    expect(adapter.transcript).to be_a(OpenLanes::Execution::Transcript)
  end
end
