# frozen_string_literal: true

require_relative "live_context"

# D9: a question an agent wrote as prose is rewritten into lettered choices
# in blocked.md itself, off the tick thread, and only ever once per text.
RSpec.describe "Converting prose questions into choices", :tree do
  include_context "with a live run"

  let(:prose) do
    "The plan has seven back-end units. A 1200-second budget is unlikely to cover them in one round."
  end
  let(:rewrite) do
    "Seven back-end units will not fit one 1200-second round.\n\na) Split the plan in two (Recommended)\n" \
      "b) Raise the budget\nc) Run it as it is\n"
  end
  let(:converter) do
    Class.new do
      def initialize(body) = (@body = body) && (@calls = [])

      attr_reader :calls
      attr_accessor :body, :error

      def model = "test/model"

      def call(heading:, body:)
        @calls << [heading, body]
        raise error if error

        OpenLanes::Live::ChoiceConverter::Result.new(body: @body, count: OpenLanes::Plans::Choices.parse(@body).options.size, model:)
      end
    end.new(rewrite)
  end
  let(:dispatcher) { OpenLanes::Engine::Dispatcher.new(runner:, sleeper: ->(_) {}, converter:) }

  def convert
    dispatcher.tick
    dispatcher.instance_variable_get(:@conversions).instance_variable_get(:@jobs).each { it.thread.join(2) }
    dispatcher.tick
  end

  def blocked_md = File.read(File.join(path_of("002.00"), "blocked.md"))
  def state = OpenLanes::Plans::PlanState.for(path_of("002.00"))

  before { allow(OpenLanes::UI).to receive(:log) }

  context "with a prose question" do
    before do
      blocked("002.00", "budget", "# Blocked\n\n## B1 Budget\n\n#{prose}\n")
      convert
    end

    it "writes the choices into blocked.md under the same heading, where the page reads them" do
      choices = OpenLanes::Plans::Choices.parse(OpenLanes::Plans::BlockedFile.bodies(blocked_md)[1])
      aggregate_failures do
        expect(blocked_md).to eq("# Blocked\n\n## B1 Budget\n\n#{rewrite}")
        expect([choices.options.size, choices.recommended.label]).to eq([3, "Split the plan in two"])
        expect(converter.calls).to eq([["B1 Budget", prose]])
      end
    end

    it "keeps the agent's words in state.json" do
      expect(state.conversions.map { it.slice("question", "original", "model", "outcome") })
        .to eq([{ "question" => 1, "original" => prose, "model" => "test/model", "outcome" => "converted" }])
    end

    it "says so in the progress log" do
      expect(OpenLanes::UI).to have_received(:log).with("questions: converted B1 to 3 choices", plan: "002.00")
    end

    it "does not send the rewrite back to the model" do
      convert
      expect(converter.calls.size).to eq(1)
    end
  end

  context "with a question already lettered" do
    before do
      blocked("002.00", "budget", "## B1 Budget\n\nFit?\n\na) Split (Recommended)\nb) Wait\n")
      convert
    end

    it { expect(converter.calls).to eq([]) }
  end

  context "with a question already answered" do
    before do
      blocked("002.00", "budget", "## B1 Budget\n\n#{prose}\n\n## A1\n\nSplit it.\n\n## B2 Rebase\n\nFirst?\n\na) Yes (Recommended)\nb) No\n")
      convert
    end

    it { expect(converter.calls).to eq([]) }
  end

  context "when the model's answer is not a D3 question" do
    before do
      converter.error = OpenLanes::Live::ChoiceConverter::Invalid.new("1 option, not 2 or more")
      blocked("002.00", "budget", "## B1 Budget\n\n#{prose}\n")
      convert
    end

    it "leaves blocked.md as it was and records why, once" do
      aggregate_failures do
        expect(blocked_md).to eq("## B1 Budget\n\n#{prose}\n")
        expect(state.conversions.map { it.slice("outcome", "note") }).to eq([{ "outcome" => "rejected", "note" => "1 option, not 2 or more" }])
        expect(OpenLanes::UI).to have_received(:log).with("questions: could not convert B1: 1 option, not 2 or more", plan: "002.00")
      end
    end

    it "does not ask again, not even from a restarted run" do
      OpenLanes::Engine::Dispatcher.new(runner:, sleeper: ->(_) {}, converter:).tick
      expect(converter.calls.size).to eq(1)
    end
  end

  context "when the call fails" do
    before do
      converter.error = RuntimeError.new("OpenRouter API error 503: busy")
      blocked("002.00", "budget", "## B1 Budget\n\n#{prose}\n")
      convert
      convert
    end

    it "leaves the question, logs why, and tries no more in this run" do
      aggregate_failures do
        expect(blocked_md).to eq("## B1 Budget\n\n#{prose}\n")
        expect(state.conversions).to eq([])
        expect(converter.calls.size).to eq(1)
        expect(OpenLanes::UI).to have_received(:log).with("questions: could not convert B1: OpenRouter API error 503: busy", plan: "002.00")
      end
    end
  end

  context "when blocked.md changes while the model is writing" do
    before do
      blocked("002.00", "budget", "## B1 Budget\n\n#{prose}\n")
      dispatcher.tick
      dispatcher.instance_variable_get(:@conversions).instance_variable_get(:@jobs).each { it.thread.join(2) }
      File.write(File.join(path_of("002.00"), "blocked.md"), "## B1 Budget\n\nSomething else entirely.\n")
      dispatcher.tick
    end

    it "throws the rewrite away" do
      aggregate_failures do
        expect(blocked_md).to eq("## B1 Budget\n\nSomething else entirely.\n")
        expect(OpenLanes::UI).to have_received(:log)
          .with("questions: could not convert B1: it changed or was answered while the model was writing", plan: "002.00")
      end
    end
  end

  context "when another machine holds the plan" do
    before do
      blocked("002.00", "budget", "## B1 Budget\n\n#{prose}\n")
      store.set(keys.claim("002.00"), "ffffffffffffffffffffffff:000000000000")
      convert
    end

    it { expect(converter.calls).to eq([]) }
  end

  context "without a key" do
    let(:converter) { nil }

    before do
      blocked("002.00", "budget", "## B1 Budget\n\n#{prose}\n")
      convert
    end

    it "leaves the question for the page's text box" do
      expect([blocked_md, state.conversions]).to eq(["## B1 Budget\n\n#{prose}\n", []])
    end
  end
end
