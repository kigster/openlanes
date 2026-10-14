# frozen_string_literal: true

# What c3po-operator wrote, turned into turns. The rule under test: a card
# the gate would not take, or that names nothing on the board, comes back as
# text with the reason, and never as something the page can send.
RSpec.describe OpenLanes::Live::Copilot::Cards do
  let(:usage) { { model: "claude-haiku-5-5", up: 1200, down: 80 } }
  let(:board) do
    { "plans" => [{ "ordinal"   => "002.00",
                    "cars"      => [{ "agent" => "luke-backend" }],
                    "questions" => [{ "id" => "002.00/B1" }] }] }
  end
  let(:turns) { described_class.turns(answer, id: "01JMSG", usage:, board:) }
  let(:kinds) { turns.map(&:kind) }
  let(:stop) do
    { card: "confirm", text: "luke has not moved in 20 minutes.",
      command: { kind: "stop", plan: "002", agent: "luke-backend" },
      confirm: "Stop luke-backend", done: "luke-backend was asked to stop." }
  end
  let(:draft) { { card: "draft", question: "002.00/B1", draft: "Ninety days.", text: "A draft:" } }

  # One card's fenced block.
  def card(json) = "```c3po\n#{json.is_a?(String) ? json : JSON.generate(json)}\n```"

  describe "prose" do
    let(:answer) { "  002 is waiting on you: B1 asks how long carts are kept.  " }

    it "is one text turn, stripped, numbered after the message, carrying the usage" do
      expect(turns.map(&:wire)).to match([include(id: "01JMSG.1",
        from: "copilot",
        kind: "text",
        text: "002 is waiting on you: B1 asks how long carts are kept.",
        usage:)])
    end

    context "when there is none" do
      let(:answer) { "  \n" }

      it "still answers, saying nothing was said" do
        expect(turns.map(&:text)).to eq([described_class::SILENT])
      end
    end

    context "when it is enormous" do
      let(:answer) { "x" * (described_class::PROSE + 50) }

      it "is cut" do
        expect(turns.first.text.length).to eq(described_class::PROSE + 1)
      end
    end
  end

  describe "a confirm card" do
    let(:answer) { "Here is what I would do.\n\n#{card(stop)}\n\nOr leave it." }

    it "sits between the prose around it, in the order written" do
      expect([kinds, turns.map(&:id)]).to eq([%w[text confirm text], %w[01JMSG.1 01JMSG.2 01JMSG.3]])
    end

    it "carries the command as the gate takes it, with no id and an empty payload" do
      expect(turns[1].fields).to eq("command" => { "kind" => "stop", "plan" => "002.00", "agent" => "luke-backend", "payload" => {} },
        "confirm" => "Stop luke-backend",
        "done" => "luke-backend was asked to stop.")
    end

    it "shows its own line above the button" do
      expect(turns[1].text).to eq("luke has not moved in 20 minutes.")
    end

    it "drops a payload, so nothing rides along that the button does not say" do
      sneaky = stop.merge(command: stop[:command].merge(payload: { text: "rm -rf" }))
      expect(described_class.turns(card(sneaky), id: "1", board:).first.fields["command"]["payload"]).to eq({})
    end

    %w[discard stop_all].each do |kind|
      it "may carry #{kind}" do
        command = kind == "stop_all" ? { kind: } : { kind:, plan: "002" }
        expect(described_class.turns(card(stop.merge(command:)), id: "1", board:).map(&:kind)).to eq(%w[confirm])
      end
    end
  end

  describe "a draft card" do
    let(:answer) { card(draft) }

    it "names the question and holds the draft" do
      expect([kinds, turns.first.fields, turns.first.text])
        .to eq([%w[draft], { "question" => "002.00/B1", "draft" => "Ninety days." }, "A draft:"])
    end

    context "when the question is written short, as the agent's prompt shows it" do
      let(:answer) { card(draft.merge(question: "002/B1")) }

      it "finds it on the board and names it in full" do
        expect([kinds, turns.first.fields["question"]]).to eq([%w[draft], "002.00/B1"])
      end
    end
  end

  # Each of these must degrade to text: a reason, the card's body, and no card.
  describe "a card the control room does not accept" do
    {
      "not JSON"                     => ["{card: confirm", /it is not JSON/],
      "a list"                       => ["[1, 2]", /one JSON object/],
      "an unknown card"              => [{ card: "send", command: { kind: "message", plan: "002" } }, /"send" is not a card/],
      "no card at all"               => [{ command: { kind: "stop" } }, /nil is not a card/],
      "a message"                    => [{ card: "confirm", command: { kind: "message", plan: "002", payload: { text: "hi" } },
                                           confirm: "Send", done: "sent" }, /"message" is not a command c3po-operator may offer/],
      "a hold"                       => [{ card: "confirm", command: { kind: "hold", plan: "002", agent: "luke-backend" },
                                           confirm: "Hold", done: "held" }, /"hold" is not a command/],
      "an answer"                    => [{ card: "confirm", command: { kind: "answer", plan: "002" }, confirm: "Answer", done: "ok" },
                                         /"answer" is not a command/],
      "a made-up kind"               => [{ card: "confirm", command: { kind: "rm_rf" }, confirm: "Go", done: "gone" }, /"rm_rf" is not/],
      "a command that is a string"   => [{ card: "confirm", command: "stop", confirm: "Stop", done: "ok" }, /needs a command object/],
      "a stop naming no agent"       => [{ card: "confirm", command: { kind: "stop", plan: "002" }, confirm: "Stop", done: "ok" },
                                         /stop needs an agent/],
      "a stop naming no plan"        => [{ card: "confirm", command: { kind: "stop", agent: "luke-backend" }, confirm: "Stop",
                                           done: "ok" }, /stop needs a plan/],
      "a plan not on the board"      => [{ card: "confirm", command: { kind: "discard", plan: "009" }, confirm: "Discard", done: "ok" },
                                         /plan 009.00 is not on this board/],
      "an agent not on that plan"    => [{ card: "confirm", command: { kind: "stop", plan: "002", agent: "rey-frontend" },
                                           confirm: "Stop", done: "ok" }, /rey-frontend is not working 002.00/],
      "no button label"              => [{ card: "confirm", command: { kind: "stop_all" }, done: "ok" }, /needs its button's label/],
      "a label that is not words"    => [{ card: "confirm", command: { kind: "stop_all" }, confirm: 7, done: "ok" },
                                         /needs its button's label/],
      "an overlong label"            => [{ card: "confirm", command: { kind: "stop_all" }, confirm: "S" * 61, done: "ok" },
                                         /longer than 60 characters/],
      "no done line"                 => [{ card: "confirm", command: { kind: "stop_all" }, confirm: "Stop all" }, /what it says once done/],
      "a draft with no question"     => [{ card: "draft", draft: "x" }, /"" is not a question id/],
      "a draft for a made-up id"     => [{ card: "draft", question: "002/../../B1", draft: "x" }, /is not a question id/],
      "a draft for another question" => [{ card: "draft", question: "002.00/B7", draft: "x" }, %r{no question 002.00/B7 is waiting}],
      "an empty draft"               => [{ card: "draft", question: "002.00/B1", draft: "  " }, /needs the draft/]
    }.each do |name, (json, reason)|
      context "with #{name}" do
        let(:answer) { card(json) }

        it "is text giving the reason and the card's body, never a card" do
          expect([kinds, turns.first.text]).to match([%w[text], match(reason).and(include("nothing was offered"))])
        end
      end
    end

    context "with no board to check it against" do
      let(:board) { nil }
      let(:answer) { "#{card(stop)}\n#{card(draft)}" }

      it "offers neither a stop nor a draft" do
        expect([kinds, turns.map(&:text)]).to match([%w[text text], [/no run is publishing a board/, %r{no question 002.00/B1}]])
      end
    end

    context "with more than three cards" do
      let(:answer) { Array.new(4) { card(stop) }.join("\n") }

      it "draws three and turns the rest into text" do
        expect(kinds).to eq(%w[confirm confirm confirm text])
      end
    end
  end

  describe "fences that are not cards" do
    {
      "a json fence"      => "```json\n#{JSON.generate(card: "confirm", command: { kind: "stop_all" }, confirm: "Stop all", done: "ok")}\n```",
      "an unclosed fence" => "```c3po\n#{JSON.generate(card: "confirm", command: { kind: "stop_all" }, confirm: "Stop all", done: "ok")}\n",
      "an indented fence" => "  ```c3po\n{}\n  ```"
    }.each do |name, answer|
      it "leaves #{name} as prose" do
        expect(described_class.turns(answer, id: "1", board:).map(&:kind)).to eq(%w[text])
      end
    end
  end
end
