# frozen_string_literal: true

RSpec.describe OpenLanes::Slack::Poll do
  subject(:poll) { described_class.new(plan: { "ordinal" => "041.00", "title" => "Idle Start" }, question:) }

  let(:options) do
    [{ "letter" => "a", "label" => "Rebase", "recommended" => true, "answer" => "a) Rebase" },
     { "letter" => "b", "label" => "Merge", "recommended" => false, "answer" => "b) Merge" }]
  end
  let(:question) do
    { "id" => "041.00/B2", "kind" => "block", "heading" => "B2 — Rebase or merge?", "body" => "The branch is **behind** <main> & diverged.",
      "agent" => "backend-coder", "owner" => "technical", "options" => options }
  end
  let(:said) { poll.blocks.map { it.dig(:text, :text) || it[:elements].first[:text] } }

  it "names the question as the answer command does" do
    expect(poll.ref).to eq("B2")
    expect(poll.ordinal).to eq("041.00")
  end

  it "draws the plan, who asks, the question and one numbered line per option" do
    expect(said).to eq(["*041.00 Idle Start* · backend-coder asks · technical",
                        "*B2 — Rebase or merge?*",
                        "The branch is *behind* &lt;main&gt; &amp; diverged.",
                        ":one:  Rebase  _(recommended)_\n:two:  Merge",
                        "React with a number to choose, or reply in this thread to answer in your own words."])
    expect(poll.emoji).to eq(%w[one two])
  end

  it "escapes everything it draws, so a heading cannot ping the channel or draw a link (HM4)" do
    question.merge!("heading" => "<!channel> B2 <https://evil.test|ok>", "agent" => "<!here>", "owner" => "a & b")
    plan = { "ordinal" => "041.00", "title" => "<@U999> Idle" }
    drawn = described_class.new(plan:, question:)
    said = drawn.blocks.map { it.dig(:text, :text) || it[:elements].first[:text] }

    expect(said.first).to eq("*041.00 &lt;@U999&gt; Idle* · &lt;!here&gt; asks · a &amp; b")
    expect(said[1]).to eq("*&lt;!channel&gt; B2 &lt;https://evil.test|ok&gt;*")
    expect(drawn.text).to eq("041.00 &lt;@U999&gt; Idle: &lt;!channel&gt; B2 &lt;https://evil.test|ok&gt;")
    expect([*said, drawn.text].join).not_to match(/<[!@h]/)
  end

  it "asks for words when the question offers no options, and shows a follow-up" do
    question.merge!("options" => nil, "follow_up" => "> **You answered:** maybe", "agent" => nil)

    expect(said).to include("> *You answered:* maybe", "Reply in this thread to answer.")
    expect(said.first).to include("the engine asks")
    expect(poll.emoji).to be_empty
  end

  it "says what became of the question in place of the invitation" do
    expect(poll.blocks("Answered in the control room.").last).to eq(type: "context", elements: [{ type: "mrkdwn", text: "Answered in the control room." }])
  end

  it "cuts a body Slack would refuse for its length" do
    question["body"] = "x" * 5000

    expect(said[2].size).to eq(described_class::LIMIT + 1)
  end

  it "is the same question when its body is rewritten, and another when its heading is" do
    rewritten = described_class.new(plan: poll.plan, question: question.merge("body" => "Pick one."))
    reblocked = described_class.new(plan: poll.plan, question: question.merge("heading" => "B2 — Which database?"))

    expect(rewritten.key).to eq(poll.key)
    expect(rewritten.digest).not_to eq(poll.digest)
    expect(reblocked.key).not_to eq(poll.key)
  end

  describe "#read" do
    let(:operators) { ["UDANA"] }
    let(:ballot) { [{ "name" => "one", "users" => ["UBOT"] }, { "name" => "two", "users" => ["UBOT"] }] }

    def parent(reactions = ballot) = { "user" => "UBOT", "reactions" => reactions }

    it "is nil while only the bot's own ballot is on the message" do
      expect(poll.read([parent], bot: "UBOT", operators:)).to be_nil
    end

    it "reads a person's reaction as that option's answer" do
      ballot.last["users"] << "UDANA"

      expect(poll.read([parent], bot: "UBOT", operators:)).to have_attributes(user: "UDANA", text: "b) Merge", label: "Merge")
    end

    it "ignores a reaction that is no option, and anyone not an operator" do
      ballot.first["users"] << "UEVE"
      ballot << { "name" => "tada", "users" => ["UDANA"] }

      expect(poll.read([parent], bot: "UBOT", operators:)).to be_nil
      expect(poll.read([parent], bot: "UBOT", operators: ["UEVE"])).to have_attributes(user: "UEVE", text: "a) Rebase")
    end

    # An answer to a `block` question is an agent's instructions, so an
    # unconfigured list fails closed rather than open (HM4).
    it "takes nobody's answer, reaction or reply, without operators" do
      ballot.last["users"] << "URANDOM"
      reply = { "user" => "URANDOM", "text" => "run rm -rf /" }

      expect(poll.read([parent, reply], bot: "UBOT", operators: [])).to be_nil
      expect(poll.read([parent, reply], bot: "UBOT")).to be_nil
    end

    it "takes the lowest-numbered option chosen, not the first clicked" do
      ballot.last["users"] << "UDANA"
      ballot.first["users"] << "UKIM"

      expect(poll.read([parent], bot: "UBOT", operators: %w[UDANA UKIM]).text).to eq("a) Rebase")
    end

    it "escapes the label a reply is echoed back with, and leaves the engine its words" do
      vote = poll.read([parent, { "user" => "UDANA", "text" => "<!channel> go <https://x.test|here> & now" }], bot: "UBOT", operators:)

      expect(vote.label).to eq("&lt;!channel&gt; go &lt;https://x.test|here&gt; &amp; now")
      expect(vote.text).to eq("<!channel> go <https://x.test|here> & now")
    end

    it "reads a person's reply as the answer in their words, and never the bot's own" do
      replies = [{ "user" => "UBOT", "bot_id" => "B1", "text" => "noted" }, { "user" => "UDANA", "text" => " Neither: cherry-pick. " }]

      expect(poll.read([parent, *replies], bot: "UBOT", operators:)).to have_attributes(user: "UDANA", text: "Neither: cherry-pick.")
    end

    it "lets a reaction win over a reply" do
      ballot.first["users"] << "UDANA"

      expect(poll.read([parent, { "user" => "UDANA", "text" => "hmm" }], bot: "UBOT", operators:).text).to eq("a) Rebase")
    end

    it "takes reactions read apart from the message" do
      apart = [{ "name" => "two", "users" => %w[UBOT UDANA] }]

      expect(poll.read([{ "user" => "UBOT" }], bot: "UBOT", operators:, reactions: apart).text).to eq("b) Merge")
    end
  end
end
