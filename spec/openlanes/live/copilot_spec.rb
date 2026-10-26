# frozen_string_literal: true

# The copilot's conversation over the in-memory store: the person's turn,
# the responder's answer, and the cards the page draws from typed turns.
RSpec.describe OpenLanes::Live::Copilot do
  subject(:copilot) { described_class.new(store:, keys:, responder: echo) }

  # Answers every message with one line, as the demo does.
  let(:echo) { ->(turn) { [turn_class.new(id: "#{turn.id}.1", from: "copilot", kind: "text", text: "heard #{turn.text}")] } }

  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:turn_class) { OpenLanes::Live::Copilot::Turn }
  let(:fixture) { JSON.parse(File.read(File.join(OpenLanes::Web::GEM_ROOT, "web/src/api/fixtures/copilot.json"))) }
  let(:stored) { store.xrange(keys.copilot).map { JSON.parse(it.fields["json"]) } }

  it "nudges the open pages for each turn it writes, since the API server, not the engine, writes them" do
    news = OpenLanes::Live::News.subscribe(store:, keys:)
    copilot.answer(copilot.say({ "id" => "01JN", "text" => "hi" }))
    expect([news.next_message(0), news.next_message(0), news.next_message(0)].map { it&.last })
      .to eq(['{"kind":"copilot"}', '{"kind":"copilot"}', nil])
  ensure
    news&.close
  end

  describe "#say" do
    context "with a message" do
      let!(:turn) { copilot.say(JSON.generate(id: "01JMSG", text: "  Why has 001 not moved?  ")) }

      it "returns the person's turn, stripped" do
        expect(turn.wire).to include(id: "01JMSG", from: "you", kind: "text", text: "Why has 001 not moved?")
      end

      it "stores the message and does not answer it: that is #answer's, run apart from the request" do
        expect(stored.map { it.values_at("id", "from") }).to eq([%w[01JMSG you]])
      end
    end

    it "takes a parsed hash as well" do
      expect(copilot.say({ "id" => "01JH", "text" => "hi" }).text).to eq("hi")
    end

    it "has no placeholder left to answer in the agent's place" do
      expect(described_class.const_defined?(:PLACEHOLDER)).to be(false)
    end

    context "with nobody to answer" do
      subject(:copilot) { described_class.new(store:, keys:) }

      it "refuses the message and stores nothing, rather than leave it waiting for ever" do
        expect { copilot.say({ "id" => "01JX", "text" => "anyone?" }) }.to raise_error(described_class::Unanswered, /not running/)
        expect(store.xlen(keys.copilot)).to eq(0)
      end
    end

    it "never calls the responder" do
      responder = ->(_) { raise "answered inside the request" }
      expect { described_class.new(store:, keys:, responder:).say({ "id" => "01JR", "text" => "hello" }) }.not_to raise_error
    end

    context "with a slash command (plan 020.00)" do
      subject(:copilot) { described_class.new(store:, keys:) }

      let(:queued) { store.xrange(keys.commands).map { JSON.parse(it.fields["json"]) } }

      context "when the engine is live" do
        before { store.set(keys.snapshot, "{}") }

        let!(:turn) { copilot.say({ "id" => "01JSTOP", "text" => "/stop 20" }) }

        it "stores the person's turn and queues the command under the message's id, with no copilot needed" do
          expect([stored.map { it["id"] }, queued]).to eq([%w[01JSTOP],
                                                           [{ "id" => "01JSTOP", "kind" => "stop_plan", "plan" => "020.00", "agent" => nil,
                                                              "payload" => { "source" => "copilot" } }]])
        end

        it "is a turn the caller must not hand to the copilot" do
          expect(turn.slash?).to be(true)
        end
      end

      it "refuses it with no engine to apply it, and stores and queues nothing" do
        expect { copilot.say({ "id" => "01JSTOP", "text" => "/restart 20" }) }
          .to raise_error(described_class::Unanswered, "no engine is running to apply /restart")
        expect([store.xlen(keys.copilot), store.xlen(keys.commands)]).to eq([0, 0])
      end

      it "answers an unknown one at once with the usage, engine or not, and queues nothing" do
        copilot.say({ "id" => "01JFROB", "text" => "/frobnicate" })
        expect(stored.map { it.values_at("id", "from") }).to eq([%w[01JFROB you], ["01JFROB.1", "copilot"]])
        expect([stored.last["text"], store.xlen(keys.commands)]).to match([start_with("Slash commands:"), 0])
      end
    end

    it "hands plain text to the copilot" do
      expect(copilot.say({ "id" => "01JP", "text" => "hi /stop" }).slash?).to be(false)
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

  describe "#answer" do
    let(:turn) { copilot.say({ "id" => "01JMSG", "text" => "hello" }) }

    it "stores the responder's answer after the message, naming it" do
      copilot.answer(turn)
      expect(stored.map { it.values_at("id", "from", "text") }).to eq([%w[01JMSG you hello], ["01JMSG.1", "copilot", "heard hello"]])
    end

    it "hands the person's turn to the responder and stores what it answers" do
      heard = []
      responder = ->(said) { heard << said.text and [turn_class.new(id: "#{said.id}.1", from: "copilot", kind: "text", text: "ok")] }
      described_class.new(store:, keys:, responder:).answer(turn)
      expect([heard, stored.last["text"]]).to eq([["hello"], "ok"])
    end

    it "answers for a responder that fails, under the id the page waits for" do
      described_class.new(store:, keys:, responder: ->(_) { raise "claude exited 1" }).answer(turn)
      expect(stored.last.values_at("id", "text")).to eq(["01JMSG.1", "copilot could not answer: claude exited 1"])
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

      it "still reports the latest usage when the newest turns carry none" do
        3.times { copilot.say({ "id" => "01JN#{it}", "text" => "more" }) }
        expect(copilot.history(count: 2)[:usage]).to eq(fixture["usage"])
      end
    end
  end

  describe "#since and #newest" do
    it "starts from 0-0 on an empty stream" do
      expect(copilot.newest).to eq("0-0")
    end

    it "reads what came after a stream id" do
      copilot.answer(copilot.say({ "id" => "01JA", "text" => "one" }))
      mark = copilot.newest
      copilot.answer(copilot.say({ "id" => "01JB", "text" => "two" }))
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
        /a confirm card's command is not one: stop needs a plan/,
      { from: "copilot", kind: "draft", fields: { "question" => "001.00/B1", "draft" => {} } } =>
        "a draft card's draft must be text",
      { from: "copilot", kind: "draft", fields: { "question" => "001.00/B1", "draft" => "  " } } =>
        "a draft card's draft must be text",
      { from: "copilot", kind: "confirm", fields: { "command" => { "kind" => "stop_all" }, "confirm" => "", "done" => "ok" } } =>
        "a confirm card's confirm must be text",
      { from: "copilot", kind: "draft", fields: { "question" => "001.00/B1", "draft" => "x", "id" => "2" } } =>
        "a draft card has no id",
      { from: "copilot", kind: "confirm", fields: { "command" => "stop_all", "confirm" => "Stop", "done" => "ok" } } =>
        "a confirm card's command is a JSON object",
      { from: "copilot", kind: "confirm",
        fields: { "command" => { "id" => "01JOLD", "kind" => "stop_all" }, "confirm" => "Stop", "done" => "ok" } } =>
        "a confirm card's command carries no id; the page mints one"
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
