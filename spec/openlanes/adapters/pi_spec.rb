# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Pi do
  subject(:adapter) { described_class.new }

  let(:invocation) { OpenLanes::Adapters::Invocation.new(prompt: "do it", root: "/repo", model: "anthropic/sonnet", effort: "low") }
  let(:argv) { adapter.argv(invocation) }

  it "runs pi in print mode with JSON output and no saved session" do
    expect(argv.first(5)).to eq(%w[pi --print --mode json --no-session])
  end

  it "passes the model and the thinking level" do
    expect(argv).to include("--model", "anthropic/sonnet", "--thinking", "low")
  end

  it "skips extensions, skills and templates when lean" do
    expect(argv).to include("--no-extensions", "--no-skills", "--no-prompt-templates")
  end

  it "ends with the prompt" do
    expect(argv.last).to eq("do it")
  end

  describe "#question_argv" do
    subject(:question) { described_class.new.question_argv("say hi", model: "a-model") }

    it { is_expected.to include("--no-tools", "--no-session", "--model", "a-model").and include("say hi") }

    it "leaves the model to the CLI when none is named" do
      expect(described_class.new.question_argv("say hi")).not_to include("a-model")
    end
  end
end
