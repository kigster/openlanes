# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Gemini do
  subject(:adapter) { described_class.new }

  let(:invocation) do
    OpenLanes::Adapters::Invocation.new(prompt: "do it",
      root: "/repo",
      model: "gemini-2.5-pro",
      effort: "high",
      denied_commands: ["git push"])
  end
  let(:argv) { adapter.argv(invocation) }
  let(:policy) { File.read(argv[argv.index("--policy") + 1]) }

  let(:policies) { Dir.mktmpdir("gemini-policies") }

  before {
    stub_const("#{described_class}::Policy::DIR", policies)
    allow(SecureRandom).to receive(:uuid).and_return("5d0c1e2a-6f0b-4a51-9a8e-1c2d3e4f5a6b")
  }

  after { FileUtils.rm_rf(policies) }

  it "names a new session, then the prompt" do
    expect(argv.first(5)).to eq(%w[gemini --session-id 5d0c1e2a-6f0b-4a51-9a8e-1c2d3e4f5a6b -p do\ it])
  end

  it "streams JSON in a trusted workspace, approving whatever its policy lets through" do
    expect(argv[5..9]).to eq(%w[-o stream-json --skip-trust --approval-mode yolo])
  end

  it "resumes a session instead of naming one, which gemini refuses together" do
    expect(adapter.argv(invocation.with(resume: "abc")).first(3)).to eq(%w[gemini -r abc])
  end

  it "passes the model" do
    expect(argv).to include("-m", "gemini-2.5-pro")
  end

  it "passes no effort, having no flag for it" do
    expect([adapter.effort("high"), argv.grep(/effort|thinking/)]).to eq([nil, []])
  end

  it "denies the forbidden commands in the policy it passes" do
    expect(policy).to include(%(toolName = "run_shell_command"\ncommandPrefix = ["git push"]))
  end

  it "withholds the web unless the agent declares the network" do
    open = adapter.argv(invocation.with(network: true))
    expect([policy, File.read(open[open.index("--policy") + 1])].map { it.include?("web_fetch") }).to eq([true, false])
  end

  it "writes one file per distinct policy" do
    expect(adapter.argv(invocation)[argv.index("--policy") + 1]).to eq(argv[argv.index("--policy") + 1])
  end

  it "resumes and enforces its denylist, but neither compacts nor confines" do
    expect([adapter.resumes?, adapter.enforces_tool_denial?, adapter.compacts?, adapter.confines?])
      .to eq([true, true, false, false])
  end

  it "offers the models it knows by name, unpriced" do
    expect([adapter.models.first.id, adapter.models.none?(&:priced?)]).to eq(["gemini-3.1-pro-preview", true])
  end

  it "reads gemini's own dialect" do
    expect(adapter.transcript).to be_a(OpenLanes::Adapters::Gemini::Stream)
  end
end
