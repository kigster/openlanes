# frozen_string_literal: true

require "inquirex-llm"

# No request leaves the machine: every example hands the judge an adapter
# double in place of Inquirex::LLM::JevAdapter.
RSpec.describe OpenLanes::Live::ChoiceJudge do
  subject(:judge) { described_class.new(adapter:, timeout: 1) }

  let(:calls) { [] }
  let(:verdict) { true }
  let(:adapter) do
    lambda_adapter = Object.new
    asked = calls
    answer = -> { verdict }
    lambda_adapter.define_singleton_method(:call) do |node, answers|
      asked << [node, answers]
      { asks_to_choose: answer.call }
    end
    lambda_adapter
  end

  it "asks Jev one boolean about the message, as an extract node over it" do
    judge.call("Which?\na) One\nb) Two")
    node, answers = calls.first
    aggregate_failures do
      expect(answers).to eq(message: "Which?\na) One\nb) Two")
      expect(node.schema.fields).to eq(asks_to_choose: :boolean)
      expect(node.from_steps).to eq([:message])
    end
  end

  it "passes Jev's answer on" do
    expect(judge.call("Which?")).to be(true)
  end

  context "when Jev says no" do
    let(:verdict) { false }

    it { expect(judge.call("Done so far: 1. x 2. y")).to be(false) }
  end

  context "when Jev is unsure" do
    let(:verdict) { nil }

    it { expect(judge.call("Which?")).to be_nil }
  end

  it "asks once per distinct text, however often the snapshot is rebuilt" do
    3.times { judge.call("Which?") }
    judge.call("Which one?")
    expect(calls.size).to eq(2)
  end

  it "asks once even when several threads ask at the same moment" do
    Array.new(8) { Thread.new { judge.call("Which?") } }.each(&:join)
    expect(calls.size).to eq(1)
  end

  context "when the request fails" do
    let(:adapter) do
      Object.new.tap { it.define_singleton_method(:call) { |*| raise Inquirex::LLM::Errors::AdapterError, "TypeSafe API error 500" } }
    end

    before { allow(OpenLanes::UI).to receive(:log) }

    it "has no verdict, and says so without the message" do
      expect(judge.call("Which?")).to be_nil
      expect(OpenLanes::UI).to have_received(:log).with("choice judge: no verdict (Inquirex::LLM::Errors::AdapterError)")
    end
  end

  context "when Jev is slower than the snapshot waits" do
    subject(:judge) { described_class.new(adapter:, timeout: 0.01) }

    let(:gate) { Queue.new }
    let(:adapter) do
      waiting = gate
      Object.new.tap { it.define_singleton_method(:call) { |*| waiting.pop && { asks_to_choose: false } } }
    end

    it "has no verdict yet, and the next snapshot finds the one that arrived" do
      expect(judge.call("Which?")).to be_nil
      gate << :go
      Timeout.timeout(1) { sleep 0.01 while judge.call("Which?").nil? }
      expect(judge.call("Which?")).to be(false)
    end
  end

  describe ".from_env" do
    it "is nil without a key" do
      expect([described_class.from_env({}), described_class.from_env("TYPESAFE_API_KEY" => " ")]).to eq([nil, nil])
    end

    it "is a judge with one, building no adapter until it is asked" do
      expect(described_class.from_env("TYPESAFE_API_KEY" => "ts-test")).to be_a(described_class)
    end
  end

  describe "the default adapter" do
    it "is Jev, unsure answers dropped" do
      built = described_class.new(api_key: "ts-test").send(:adapter)
      expect([built.class, built.min_confidence]).to eq([Inquirex::LLM::JevAdapter, described_class::MIN_CONFIDENCE])
    end
  end
end
