# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Grok do
  subject(:adapter) { described_class.new }

  let(:invocation) do
    OpenLanes::Adapters::Invocation.new(prompt: "do it",
      root: "/repo",
      model: "grok-4.7",
      effort: "max",
      denied_commands: ["git push", "gh pr merge"])
  end
  let(:argv) { adapter.argv(invocation) }

  before { allow(SecureRandom).to receive(:uuid).and_return("4f1c2a8e-0000-4000-8000-000000000001") }

  it "starts a session under an id of its own choosing, then the prompt" do
    expect(argv.first(5)).to eq(%w[grok -s 4f1c2a8e-0000-4000-8000-000000000001 -p do\ it])
  end

  it "streams JSON, rooted at the checkout, approving every tool the denylist lets through" do
    expect(argv[5..9]).to eq(%w[--output-format streaming-json --cwd /repo --always-approve])
  end

  it "resumes a session rather than naming a new one" do
    expect(adapter.argv(invocation.with(resume: "abc")).first(3)).to eq(%w[grok -r abc])
  end

  it "passes the model" do
    expect(argv).to include("-m", "grok-4.7")
  end

  it "maps max effort onto grok's top level" do
    expect(argv).to include("--reasoning-effort", "xhigh")
  end

  it "leaves an unknown effort to grok's default" do
    expect(adapter.argv(invocation.with(effort: nil))).not_to include("--reasoning-effort")
  end

  it "denies each forbidden command as a shell rule grok refuses itself" do
    expect(argv.each_cons(2).select { it.first == "--deny" }.map(&:last)).to eq(["Bash(git push*)", "Bash(gh pr merge*)"])
  end

  it "removes the tools that wait on a person or reach past the run" do
    expect(argv).to include("--disallowed-tools", "ask_user_question,enter_plan_mode,exit_plan_mode,scheduler_create,send_feedback")
  end

  it "closes web search unless the agent declares the network" do
    expect([argv, adapter.argv(invocation.with(network: true))].map { it.include?("--disable-web-search") }).to eq([true, false])
  end

  it "enforces the denylist and compacts with /compact, but cannot confine an agent" do
    expect([adapter.enforces_tool_denial?, adapter.compacts?, adapter.compact_prompt, adapter.confines?])
      .to eq([true, true, "/compact", false])
  end

  describe "#transcript" do
    it "reads grok's own dialect" do
      expect(adapter.transcript).to be_a(OpenLanes::Adapters::Grok::Stream)
    end

    it "knows the session its argv started" do
      expect(adapter.transcript(argv:).session).to eq("4f1c2a8e-0000-4000-8000-000000000001")
    end

    it "knows the session its argv resumed" do
      expect(adapter.transcript(argv: adapter.argv(invocation.with(resume: "abc"))).session).to eq("abc")
    end

    it "knows none without an argv" do
      expect(adapter.transcript.session).to be_nil
    end
  end
end
