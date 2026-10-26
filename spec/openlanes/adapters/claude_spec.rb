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

  describe "what a plan agent does not get" do
    it "asks for the one-line status tool, with no fixed tool set and no extra directory" do
      expect([argv.include?("--brief"), argv.include?("--tools"), argv.include?("--restricted"), argv.count("--add-dir")])
        .to eq([true, false, false, 1])
    end
  end

  describe "the copilot's invocation" do
    let(:copilot) do
      adapter.argv(invocation.with(brief: false, dirs: ["/tmp/traces"], tools: %w[Read Grep Glob Bash], system: "You are copilot."))
    end

    def flag(name) = copilot[copilot.index(name) + 1]

    it "fixes the tool set, ignores settings files, and refuses what is not allowed rather than ask" do
      expect([flag("--tools"), copilot.include?("--restricted"), flag("--permission-mode")])
        .to eq(["Read,Grep,Glob,Bash", true, "dontAsk"])
    end

    it "reads one more directory" do
      expect(copilot.each_cons(2).select { it.first == "--add-dir" }.map(&:last)).to eq(["/repo", "/tmp/traces"])
    end

    it "sends its standing instructions as the system prompt, and leaves the status tool out" do
      expect([flag("--append-system-prompt"), copilot.include?("--brief")]).to eq(["You are copilot.", false])
    end

    it "resumes, which the adapter says it can" do
      expect([adapter.resumes?, adapter.argv(invocation.with(resume: "s1")).each_cons(2).to_a.include?(["--resume", "s1"])])
        .to eq([true, true])
    end
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
