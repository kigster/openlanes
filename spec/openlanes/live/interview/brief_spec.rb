# frozen_string_literal: true

RSpec.describe OpenLanes::Live::Interview::Brief do
  let(:turn) { OpenLanes::Live::Interview::Turn }

  it "opens an empty interview with the rules, the question and the documents" do
    text = described_class.new(question: "## B1 Rebase\n\nShould I?", history: [], documents: { "spec.md" => "the spec" }).to_s
    expect(text).to include("one question at a time", "Never use bare labels", "Should I?", "## spec.md\n\nthe spec", "Nothing yet")
  end

  it "carries the conversation so far, and why a reply must be said again" do
    history = [turn.new(id: "r1", from: "you", kind: "text", text: "maybe")]
    text = described_class.new(question: "Q", history:, rephrase: "B2 is a bare label").to_s
    expect(text).to include('you: {"kind":"text","text":"maybe"}', "could not be shown (B2 is a bare label)")
  end
end
