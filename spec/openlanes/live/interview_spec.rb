# frozen_string_literal: true

# The unblocker's interview on one question, over the in-memory store.
RSpec.describe OpenLanes::Live::Interview do
  subject(:interview) { described_class.new(store:, keys:, plan: "068.00", number: 2) }

  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:turn) { OpenLanes::Live::Interview::Turn }
  let(:options) { [{ label: "Redis", recommended: true }, { label: "Postgres", recommended: false }] }
  let(:question) { turn.new(id: "q1", from: "unblocker", kind: "question", text: "Where should sessions live?", options:) }

  it "keeps the conversation per plan and question, so a second reader sees the same turns" do
    interview.say(question)
    interview.say(turn.new(id: "r1", from: "you", kind: "text", text: "Redis, I think"))
    again = described_class.new(store:, keys:, plan: "068.00", number: "2")
    expect(again.history.map(&:id)).to eq(%w[q1 r1])
    expect(described_class.new(store:, keys:, plan: "068.00", number: 3).history).to be_empty
  end

  it "serves turns as the wire carries them, options on a question only" do
    interview.say(question)
    wire = interview.wire[:turns].first
    expect(wire).to include(id: "q1", from: "unblocker", kind: "question", options:)
    expect(wire).not_to have_key(:answer)
  end

  it "finds a decision by its id, and nothing else by it" do
    interview.say(question)
    interview.say(turn.new(id: "d1", from: "unblocker", kind: "decision", text: "Keep sessions in Redis?", answer: "a) Redis"))
    expect(interview.decision("d1").answer).to eq("a) Redis")
    expect(interview.decision("q1")).to be_nil
  end

  it "forgets everything on close" do
    interview.say(question)
    interview.close
    expect(interview.history).to be_empty
  end

  describe "#reply" do
    let(:asked) { [] }
    let(:responder) do
      lambda do |talk|
        asked << talk.history.size
        [turn.new(id: talk.next_id, from: "unblocker", kind: "text", text: "Tell me more")]
      end
    end

    it "answers only when the person is owed a turn, so a second read of an empty interview adds nothing" do
      2.times { interview.reply(responder) }
      expect(interview.history.map(&:from)).to eq(%w[unblocker])
      interview.say(turn.new(id: "r1", from: "you", kind: "text", text: "ok"))
      interview.reply(responder)
      expect(interview.history.map(&:from)).to eq(%w[unblocker you unblocker])
      expect(interview.history.map(&:id).uniq.size).to eq(3)
    end

    it "leaves a reply under way alone, so a reload during a slow turn stores one opening, not two" do
      inner = nil
      slow = lambda do |talk|
        inner = talk.reply(responder) # a second caller, while this one holds the interview
        responder.call(talk)
      end
      interview.reply(slow)
      expect(inner).to eq([])
      expect(interview.history.map(&:from)).to eq(%w[unblocker])
    end
  end

  it "accepts a bare label in a decision's answer: those are the person's words" do
    decision = turn.new(id: "d1", from: "unblocker", kind: "decision", text: "Settle it?", answer: "like B2 said")
    expect(decision.answer).to eq("like B2 said")
  end

  it "nudges the open pages for each turn" do
    news = OpenLanes::Live::News.subscribe(store:, keys:)
    interview.say(question)
    expect(news.next_message(0)&.last).to eq('{"kind":"interview"}')
  ensure
    news&.close
  end

  describe OpenLanes::Live::Interview::Turn do
    {
      "a bare label in a question"               => [{ kind: "question", text: "Is B2 still right?" }, /B2 is a bare label/],
      "a bare label in a decision's text"        => [{ kind: "decision", text: "Settle it as A9 said?", answer: "yes" }, /A9/],
      "a question with every option recommended" => [{ kind: "question", text: "Which?", options: :all }, /exactly one/],
      "a question with one option"               => [{ kind: "question", text: "Which?", options: :one }, /2 to 5/],
      "a decision with no answer"                => [{ kind: "decision", text: "Settle it?" }, /needs an answer/],
      "an unknown kind"                          => [{ kind: "card", text: "hi" }, /unknown kind/],
      "an empty turn"                            => [{ kind: "text", text: " " }, /needs text/]
    }.each do |what, (args, why)|
      it "refuses #{what}" do
        picked = { all: options.map { it.merge(recommended: true) }, one: options.take(1) }.fetch(args[:options], options)
        args = args.merge(options: picked) if args[:kind] == "question"
        expect { turn.new(id: "x", from: "unblocker", **args) }.to raise_error(OpenLanes::Live::Interview::Invalid, why)
      end
    end

    it "lets a person's plain text through, labels and all" do
      expect(turn.new(id: "y", from: "you", kind: "text", text: "like B2 said").text).to eq("like B2 said")
    end

    it "refuses a person's question card" do
      expect { turn.new(id: "y", from: "you", kind: "question", text: "Which?", options:) }
        .to raise_error(OpenLanes::Live::Interview::Invalid, /only the unblocker/)
    end

    it "parses what it wrote" do
      expect(turn.parse(JSON.parse(question.to_json)).options).to eq(options)
    end
  end
end
