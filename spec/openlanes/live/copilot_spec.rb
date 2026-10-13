# frozen_string_literal: true

# The copilot's conversation over the in-memory store: the person's turn,
# the placeholder's answer, and the cards the page draws from typed turns.
RSpec.describe OpenLanes::Live::Copilot do
  subject(:copilot) { described_class.new(store:, keys:) }

  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:turn_class) { OpenLanes::Live::Copilot::Turn }
  let(:fixture) { JSON.parse(File.read(File.join(OpenLanes::Web::GEM_ROOT, "web/src/api/fixtures/copilot.json"))) }
  let(:stored) { store.xrange(keys.copilot).map { JSON.parse(it.fields["json"]) } }

  describe "#say" do
    context "with a message" do
      let!(:turn) { copilot.say(JSON.generate(id: "01JMSG", text: "  Why has 001 not moved?  ")) }

      it "returns the person's turn, stripped" do
        expect(turn.wire).to include(id: "01JMSG", from: "you", kind: "text", text: "Why has 001 not moved?")
      end

      it "stores the message, then the placeholder's answer naming it" do
        expect(stored.map { it.values_at("id", "from") }).to eq([%w[01JMSG you], %w[01JMSG.1 copilot]])
      end

      it "answers that nobody is listening yet" do
        expect(stored.last["text"]).to start_with("c3po-operator is not built yet, so nobody is listening here.")
      end
    end

    it "takes a parsed hash as well" do
      expect(copilot.say({ "id" => "01JH", "text" => "hi" }).text).to eq("hi")
    end

    it "hands the person's turn to the responder and stores what it answers" do
      heard = []
      responder = ->(turn) { heard << turn.text and [turn_class.new(id: "#{turn.id}.1", from: "copilot", kind: "text", text: "ok")] }
      described_class.new(store:, keys:, responder:).say({ "id" => "01JR", "text" => "hello" })
      expect([heard, stored.last["text"]]).to eq([["hello"], "ok"])
    end

    {
      "[1, 2]"                                  => "a message is a JSON object",
      "{nope"                                   => /not a message/,
      '{"id": "bad id!", "text": "x"}'          => /id must be/,
      '{"id": "01J", "text": "   "}'            => "a message needs text",
      %({"id": "01J", "text": "#{"x" * 4001}"}) => "a message is at most 4000 characters"
    }.each do |body, reason|
      it "refuses #{body[0, 30]} and stores nothing" do
        expect { copilot.say(body) }.to raise_error(described_class::Invalid, reason)
        expect(store.xlen(keys.copilot)).to eq(0)
      end
    end
  end

  describe "#history" do
    it "is empty, with no model and no tokens, before anything was said" do
      expect(copilot.history).to eq(turns: [], usage: { model: nil, up: 0, down: 0 })
    end

    context "with the fixture's conversation stored" do
      before { fixture["turns"].each { store.xadd(keys.copilot, { json: JSON.generate(it) }) } }

      it "reads the turns oldest first" do
        expect(copilot.history[:turns].map { it["id"] }).to eq(fixture["turns"].map { it["id"] })
      end

      it "reports the copilot's latest usage" do
        expect(copilot.history[:usage]).to eq(fixture["usage"])
      end

      it "keeps only the newest when asked for fewer" do
        expect(copilot.history(count: 2)[:turns].map { it["kind"] }).to eq(%w[text confirm])
      end
    end
  end

  describe "#since and #newest" do
    it "starts from 0-0 on an empty stream" do
      expect(copilot.newest).to eq("0-0")
    end

    it "reads what came after a stream id" do
      copilot.say({ "id" => "01JA", "text" => "one" })
      mark = copilot.newest
      copilot.say({ "id" => "01JB", "text" => "two" })
      expect(copilot.since(mark).map { it.last["id"] }).to eq(%w[01JB 01JB.1])
    end
  end

  describe described_class::Turn do
    it "round-trips every turn of the page's fixture, card fields and all" do
      expect(fixture["turns"].map { JSON.parse(described_class.parse(it).to_json) }).to eq(fixture["turns"])
    end

    it "stamps a turn with the time when the wire carries none" do
      expect(described_class.parse("id" => "1", "from" => "you", "kind" => "text", "text" => "x").at).to be_a(Time)
    end

    {
      { from: "operator", kind: "text" }                      => /unknown speaker/,
      { from: "copilot", kind: "poem" }                       => /unknown kind "poem"/,
      { from: "you", kind: "draft", fields: { "question" => "001.00/B1", "draft" => "x" } } => "only the copilot draws cards",
      { from: "copilot", kind: "draft", fields: { "draft" => "x" } } => "a draft card needs question",
      { from: "copilot", kind: "confirm", fields: { "command" => { "kind" => "stop" }, "confirm" => "Stop", "done" => "ok" } } =>
        /a confirm card's command is not one: stop needs a plan/
    }.each do |attrs, reason|
      it "refuses #{attrs.except(:fields)} as #{reason}" do
        expect { described_class.new(id: "1", text: "x", **attrs) }.to raise_error(OpenLanes::Live::Copilot::Invalid, reason)
      end
    end

    it "refuses a time that is not one" do
      expect { described_class.parse("id" => "1", "from" => "you", "kind" => "text", "at" => "soon") }
        .to raise_error(OpenLanes::Live::Copilot::Invalid, /not a turn/)
    end
  end
end
