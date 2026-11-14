# frozen_string_literal: true

# The demo's canned interview: two questions, then a decision in the person's words.
RSpec.describe OpenLanes::Web::Demo::Interview do
  let(:interview) { OpenLanes::Live::Interview.new(store: OpenLanes::Live.memory_store, keys:, plan: "001.00", number: 1) }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:turn) { OpenLanes::Live::Interview::Turn }

  def say(id, text) = interview.say(turn.new(id:, from: "you", kind: "text", text:))

  it "ends on a decision even when the person's words carry a label" do
    interview.reply(described_class)
    say("r1", "like B2 said")
    interview.reply(described_class)
    say("r2", "Nothing more, keep it simple")
    decision = interview.reply(described_class).last
    expect([decision.kind, decision.answer]).to eq(["decision", "like B2 said; Nothing more, keep it simple"])
  end
end
