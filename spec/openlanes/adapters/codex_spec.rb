# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Codex do
  subject(:adapter) { described_class.new }

  let(:invocation) do
    OpenLanes::Adapters::Invocation.new(prompt: "do it", root: "/repo", model: "gpt-5-codex", effort: "max")
  end
  let(:argv) { adapter.argv(invocation) }

  it "runs codex exec in its workspace sandbox, rooted at the checkout" do
    expect(argv.first(7)).to eq(%w[codex exec --json --sandbox workspace-write --cd /repo])
  end

  it "ends with the prompt" do
    expect(argv.last).to eq("do it")
  end

  it "maps max effort onto codex's top level" do
    expect(argv).to include("--config", 'model_reasoning_effort="xhigh"')
  end

  it "ignores the operator's config when lean" do
    expect(argv).to include("--ignore-user-config")
  end

  it "opens the network only for an agent that declares it" do
    expect([argv, adapter.argv(invocation.with(network: true))].map { |a| a.include?("sandbox_workspace_write.network_access=true") })
      .to eq([false, true])
  end

  it "does not claim to enforce the command denylist" do
    expect(adapter.enforces_tool_denial?).to be(false)
  end

  it "reads its stream generically" do
    expect(adapter.transcript).to be_a(OpenLanes::Adapters::Stream)
  end
end
