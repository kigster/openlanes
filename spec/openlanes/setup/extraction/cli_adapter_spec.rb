# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::Extraction::CliAdapter do
  subject(:adapter) { described_class.new(command: ->(prompt) { ["agent", prompt] }, runner:, label: "agent") }

  let(:runner) { instance_double(OpenLanes::Adapters::ProbeRunner, call: result) }
  let(:result) { OpenLanes::Adapters::ProbeRunner::Result.new(stdout: "Here you go:\n```json\n{\"ci\":\"circleci\"}\n```\n", stderr: "", status: 0) }
  let(:node) { Inquirex::LLM::Node.new(id: :stack, verb: :extract, prompt: "read", schema: Inquirex::LLM::Schema.new(ci: :string), from_steps: [:description]) }

  it "keeps the JSON a CLI printed among its own words" do
    expect(adapter.call(node, { description: "a shop" })[:ci]).to eq("circleci")
  end

  it "hands the CLI the instructions and the description" do
    adapter.call(node, { description: "a shop" })
    expect(runner).to have_received(:call).with("agent", include("JSON", "a shop"))
  end

  context "when the CLI fails" do
    let(:result) { OpenLanes::Adapters::ProbeRunner::Result.new(stdout: "", stderr: "said: a shop", status: 3) }

    it "says how without repeating what it printed" do
      expect { adapter.call(node, { description: "a shop" }) }.to raise_error(Inquirex::LLM::Errors::AdapterError, "agent exited 3")
    end
  end
end
