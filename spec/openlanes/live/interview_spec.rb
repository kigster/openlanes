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

  # Issue 252: two turns of one reply share a second, and their ids are
  # random, so nothing but the stream's own order says which came first.
  describe "the order of turns" do
    let(:at) { Time.utc(2026, 11, 14, 9, 0, 0) }
    let(:reply) do
      [turn.new(id: "uZZZ", from: "unblocker", kind: "text", text: "Understood.", at:),
       turn.new(id: "uAAA", from: "unblocker", kind: "decision", text: "Keep sessions in Redis?", answer: "Redis", at:)]
    end

    it "gives each stored turn the next place in the conversation, whatever its time and id" do
      said = reply.map { interview.say(it) }
      seqs = said.map { it.seq.split("-").map(&:to_i) }
      aggregate_failures do
        expect(seqs).to eq(seqs.sort).and eq(seqs.uniq)
        expect(interview.history.map(&:seq)).to eq(said.map(&:seq))
        expect(interview.wire[:turns].map { it.values_at(:kind, :at) }).to eq([["text", at.iso8601], ["decision", at.iso8601]])
        expect(interview.wire[:turns].map { it[:seq] }).to eq(said.map(&:seq))
      end
    end

    it "sends the place with the turn on the event stream" do
      said = reply.map { interview.say(it) }
      events = OpenLanes::Live::Interview::Feed.new(store:, keys:).since("0-0").map { it.last["turn"] }
      expect(events.map { it["seq"] }).to eq(said.map(&:seq))
    end

    it "has no place before it is stored, and stores none inside the turn" do
      expect(reply.first.wire).not_to have_key(:seq)
      interview.say(reply.first)
      expect(JSON.parse(store.xrange(keys.interview("068.00", 2)).first.fields["json"])).not_to have_key("seq")
    end
  end

  describe "#about" do
    before do
      interview.about("first asking")
      interview.say(question)
    end

    it "keeps the conversation while the question is the one it was asked about" do
      interview.about("first asking")
      expect(interview.history.map(&:id)).to eq(%w[q1])
    end

    it "forgets a conversation about an earlier question" do
      interview.about("second asking")
      expect(interview.history).to be_empty
      interview.say(question)
      interview.about("second asking")
      expect(interview.history.map(&:id)).to eq(%w[q1])
    end

    it "forgets one nobody recorded the question of" do
      interview.close
      interview.say(question)
      interview.about("first asking")
      expect(interview.history).to be_empty
    end
  end

  describe ".topic", :tree do
    let(:subject_of) { ->(ordinal) { OpenLanes::Plans.tree(plans_root).find(OpenLanes::Plans::Ordinal.parse(ordinal)) } }
    let(:asked) { "# Blocked\n\n## B1 Rebase\n\nShould I rebase?\n" }

    def block(text) = plans { |t| t.plan "002.00", :blocked, "rebase", files: { "spec.md" => "# Spec\n", "blocked.md" => text } }

    it "names the question by what it asks, so a new B1 is another question" do
      block(asked)
      first = described_class.topic(subject_of["002.00"], 1)
      File.write(File.join(subject_of["002.00"].feature.path, "blocked.md"), "# Blocked\n\n## B1 Database\n\nPostgres or SQLite?\n")
      aggregate_failures do
        expect(first).to match(/\A\h{64}\z/)
        expect(described_class.topic(subject_of["002.00"], "1")).to match(/\A\h{64}\z/)
        expect(described_class.topic(subject_of["002.00"], 1)).not_to eq(first)
      end
    end

    it "is nil for a question that is answered, and for one the plan does not ask" do
      block("#{asked}\n## A1\n\nyes\n")
      expect([described_class.topic(subject_of["002.00"], 1), described_class.topic(subject_of["002.00"], 2)]).to eq([nil, nil])
    end
  end

  it "offers no decision once anything was said after it" do
    interview.say(turn.new(id: "d1", from: "unblocker", kind: "decision", text: "Keep sessions in Redis?", answer: "Redis"))
    interview.say(turn.new(id: "r1", from: "you", kind: "text", text: "wait, Postgres"))
    expect(interview.decision("d1")).to be_nil
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

    # Issue 252: the person corrects themselves while the model runs.
    context "when the person says more while a reply is being written" do
      let(:read) { [] }
      let(:late) { ->(n) { turn.new(id: "late#{n}", from: "you", kind: "text", text: "wait, no: Postgres (#{n})") } }
      let(:deciding) do
        lambda do |talk|
          read << talk.history.select { it.from == "you" }.map(&:id)
          talk.say(late[read.size]) if read.size <= interruptions
          [turn.new(id: talk.next_id, from: "unblocker", kind: "decision", text: "Settle it?", answer: "having read #{read.last.join(",")}")]
        end
      end
      let(:interruptions) { 1 }

      before do
        interview.say(question)
        interview.say(turn.new(id: "r1", from: "you", kind: "text", text: "Redis"))
      end

      it "discards the reply that never read it, and answers again" do
        stored = interview.reply(deciding)
        aggregate_failures do
          expect(read).to eq([%w[r1], %w[r1 late1]])
          expect(interview.history.map(&:id).first(3)).to eq(%w[q1 r1 late1])
          expect(interview.history.map(&:kind)).to eq(%w[question text text decision])
          expect(stored.map(&:answer)).to eq(["having read r1,late1"])
          expect(interview.decision(stored.last.id)&.answer).to eq("having read r1,late1")
        end
      end

      context "when they never stop" do
        let(:interruptions) { 99 }

        it "gives up after a few replies, and offers nothing to confirm" do
          stored = interview.reply(deciding)
          aggregate_failures do
            expect(read.size).to eq(described_class::ATTEMPTS)
            expect(stored.map { [it.kind, it.text] }).to eq([["text", described_class::LATE]])
            expect(interview.history.map(&:kind)).not_to include("decision")
          end
        end
      end

      context "when their turn lands between the last look and the write" do
        let(:interruptions) { 0 }

        it "says so over the reply that missed it, and answers again" do
          slipped = false
          allow(store).to receive(:xadd).and_wrap_original do |original, key, fields, **options|
            if fields[:json].to_s.include?('"decision"') && !slipped
              slipped = true
              interview.say(late[0])
            end
            original.call(key, fields, **options)
          end
          stored = interview.reply(deciding)
          aggregate_failures do
            expect(interview.history.map(&:id).first(4)).to eq(["q1", "r1", "late0", stored.first.id])
            expect(stored.map { [it.kind, it.text] }).to eq([["decision", "Settle it?"], ["text", described_class::MORE], ["decision", "Settle it?"]])
            expect(stored.last.answer).to eq("having read r1,late0")
            expect(interview.decision(stored.first.id)).to be_nil
          end
        end
      end
    end

    it "drops a reply whose conversation was closed while it was written" do
      interview.about("first asking")
      closing = lambda do |talk|
        talk.close
        responder.call(talk)
      end
      expect([interview.reply(closing), interview.history]).to eq([[], []])
    end

    it "answers for a responder that fails in plain words" do
      text = interview.reply(->(_) { raise OpenLanes::Error, "claude reported: usage limit reached\nand more" }).first.text
      expect(text).to eq("The interview could not go on (claude reported: usage limit reached). The answer buttons still work.")
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

    # Issue 252: each of these raised NoMethodError, which the page showed raw.
    {
      "options that are words"       => { "kind" => "question", "text" => "Which?", "options" => %w[yes no] },
      "options that are one string"  => { "kind" => "question", "text" => "Which?", "options" => "yes or no" },
      "a time that is not a time"    => { "kind" => "text", "text" => "hi", "at" => 12 },
      "something that is not a turn" => "just words"
    }.each do |what, data|
      it "reads #{what} as output it cannot draw" do
        data = data.merge("id" => "x", "from" => "unblocker") if data.is_a?(Hash)
        expect { turn.parse(data) }.to raise_error(OpenLanes::Live::Interview::Invalid)
      end
    end

    it "reads an answer that is not text as text" do
      expect(turn.parse("id" => "x", "from" => "unblocker", "kind" => "decision", "text" => "Settle it?", "answer" => 42).answer).to eq("42")
    end
  end
end
