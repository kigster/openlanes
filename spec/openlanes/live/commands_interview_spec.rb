# frozen_string_literal: true

require_relative "live_context"

# Confirming the unblocker's interview writes the decision as the answer,
# byte for byte as the answer box would, and only once.
RSpec.describe OpenLanes::Live::Commands, :tree do
  subject(:commands) do
    described_class.new(store:, keys:, node:, run_state:, claims:, clock: -> { Time.utc(2026, 10, 13, 9) })
  end

  include_context "with a live run"

  let(:interview) { OpenLanes::Live::Interview.new(store:, keys:, plan: "002.00", number: 1) }
  let(:turn) { OpenLanes::Live::Interview::Turn }
  let(:blocked_md) { File.read(File.join(path_of("002.00"), "blocked.md")) }

  def send_command(kind, id:, **payload) = OpenLanes::Live.enqueue(store:, keys:, input: { id:, kind:, plan: "002.00", agent: nil, payload: })

  def apply = commands.call(dispatcher)

  before do
    blocked("002.00", "rebase", "# Blocked\n\n## B1 Rebase\n\nShould I rebase?\n\na) yes (Recommended)\nb) no\n")
    interview.say(turn.new(id: "q1",
      from: "unblocker",
      kind: "question",
      text: "Should the branch be rebased?",
      options: [{ label: "yes", recommended: true }, { label: "no", recommended: false }]))
    interview.say(turn.new(id: "d1", from: "unblocker", kind: "decision", text: "Rebase onto main?", answer: "a) yes"))
  end

  it "writes exactly what the answer box writes for the same text" do
    send_command("confirm_interview", id: "C1", question: "1", turn: "d1")
    apply
    confirmed = blocked_md
    File.write(File.join(path_of("002.00"), "blocked.md"), "# Blocked\n\n## B1 Rebase\n\nShould I rebase?\n\na) yes (Recommended)\nb) no\n")
    send_command("answer", id: "C1", question: "B1", text: "a) yes")
    store.hdel(keys.done, "C1")
    apply
    expect(confirmed).to eq(blocked_md)
  end

  it "writes the decision as the answer, and forgets the interview" do
    send_command("confirm_interview", id: "C1", question: "1", turn: "d1")
    expect(apply.map(&:status)).to eq(%w[done])
    aggregate_failures do
      expect(blocked_md).to include("## A1\n\na) yes\n\nAnswered by dana on 2026-10-13\n<!-- cmd:C1 -->\n")
      expect(interview.history).to be_empty
    end
  end

  it "refuses a second confirm" do
    send_command("confirm_interview", id: "C1", question: "1", turn: "d1")
    send_command("confirm_interview", id: "C2", question: "1", turn: "d1")
    expect(apply.map { [it.status, it.reason] }.last).to eq(["refused", "this question already has an answer waiting"])
  end

  it "refuses a confirm after a button answer" do
    send_command("answer", id: "C1", question: "B1", text: "b) no")
    send_command("confirm_interview", id: "C2", question: "1", turn: "d1")
    aggregate_failures do
      expect(apply.map(&:status)).to eq(%w[done refused])
      expect(blocked_md.scan("## A1").size).to eq(1)
    end
  end

  it "refuses a turn that is not a decision" do
    send_command("confirm_interview", id: "C1", question: "1", turn: "q1")
    expect(apply.map(&:reason)).to eq(["the interview has no decision q1 to confirm"])
  end
end
