# frozen_string_literal: true

require_relative "../../support/fake_slack"

RSpec.describe OpenLanes::Slack::Bridge do
  subject(:bridge) { described_class.new(room:, outbox: OpenLanes::Slack::Outbox.new(store:, keys:), clock: -> { now }) }

  let(:slack) { FakeSlack.new }
  let(:room) { OpenLanes::Slack::Room.new(api: slack.api, channel: "#questions", operators: ["UDANA"]) }
  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/example/openlanes", node: "aaaa:bbbb") }
  let(:options) do
    [{ letter: "a", label: "Rebase", recommended: true, answer: "a) Rebase" },
     { letter: "b", label: "Merge", recommended: false, answer: "b) Merge" }]
  end
  let(:question) do
    { id: "041.00/B1", number: 1, kind: "block", heading: "B1 — Rebase or merge?", body: "The branch diverged.",
      agent: "backend-coder", owner: "technical", options:, held: false }
  end

  def now = @now ||= Time.utc(2026, 11, 14, 9)

  def snapshot(*questions) = { plans: [{ ordinal: "041.00", title: "Idle Start", questions: }, { ordinal: "042.00", title: "Quiet", questions: [] }] }

  def later(seconds) = @now = now + seconds

  # A tick's worth: this tick's questions, one pass over Slack, and the loop's hook.
  def round(*questions)
    bridge.offer(snapshot(*questions))
    bridge.cycle
    bridge.call
  end

  def queued = store.xrange(keys.commands).map { JSON.parse(it.fields["json"]) }

  def kept = store.hgetall(keys.slack).transform_values { JSON.parse(it) }

  before { allow(OpenLanes::UI).to receive(:log) }

  it "does nothing until the engine has published a board" do
    bridge.cycle

    expect(slack.calls).to be_empty
  end

  it "posts each question once, with its ballot, and writes down where" do
    3.times { round(question) }

    expect(slack.posts.size).to eq(1)
    expect(slack.text_of(slack.posts.first)).to include("041.00 Idle Start", "B1 — Rebase or merge?", ":one:  Rebase")
    expect(slack.called("reactions.add").map { it["name"] }).to eq(%w[one two])
    expect(kept.values.first).to include("channel" => "C0QUESTIONS", "ts" => slack.posts.first, "state" => "open")
  end

  it "leaves the store to the loop: nothing is written until the hook runs" do
    bridge.offer(snapshot(question))
    bridge.cycle

    expect(kept).to be_empty
    bridge.call
    expect(kept.size).to eq(1)
  end

  it "turns a reaction into the page's own answer command, signed with who gave it" do
    round(question)
    slack.click(slack.posts.first, "two")
    round(question)

    expect(queued).to contain_exactly(include("kind" => "answer",
      "plan" => "041.00",
      "agent" => "backend-coder",
      "payload" => { "question" => "B1", "text" => "b) Merge\n\n(via Slack, Dana Okafor)" }))
    expect(queued.first["id"]).to match(/\Aslack-\h{32}\z/)
    expect(slack.text_of(slack.posts.first)).to end_with(":white_check_mark: Answered by <@UDANA>: Merge")
  end

  it "turns a reply in the thread into an answer in the person's words" do
    round(question.merge(options: nil))
    slack.say(slack.posts.first, "Neither, cherry-pick it")
    round(question.merge(options: nil))

    expect(queued.first.dig("payload", "text")).to eq("Neither, cherry-pick it\n\n(via Slack, Dana Okafor)")
  end

  it "sends the engine's own questions the bare choice, which is all they read" do
    extension = question.merge(id: "041.00/X3", kind: "extension", heading: "X3 — More time?")
    round(extension)
    slack.click(slack.posts.first, "one")
    round(extension)

    expect(queued.first["payload"]).to eq("question" => "X3", "text" => "a) Rebase")
  end

  it "answers once, however long the answered question stays asked" do
    round(question)
    slack.click(slack.posts.first, "one")
    3.times { round(question) }

    expect(queued.size).to eq(1)
  end

  it "reads a different open poll each cycle" do
    other = question.merge(id: "041.00/B2", heading: "B2 — Which database?")
    4.times { round(question, other) }

    expect(slack.called("conversations.replies").map { it["ts"] }.uniq.size).to eq(2)
  end

  it "redraws a poll whose question was rewritten into choices, in place" do
    round(question.merge(options: nil, body: "Rebase, or merge?"))
    round(question)

    expect(slack.posts.size).to eq(1)
    expect(slack.text_of(slack.posts.first)).to include(":two:  Merge")
    expect(slack.called("reactions.add").size).to eq(2)
  end

  describe "a question that is no longer asked" do
    before { round(question) }

    it "keeps its poll open through a snapshot or two without it" do
      round
      later(described_class::GRACE - 1)
      round

      expect(slack.text_of(slack.posts.first)).to include("React with a number")
      expect(kept.size).to eq(1)
    end

    it "closes the poll once it has stayed away, and forgets it" do
      round
      later(described_class::GRACE)
      round

      expect(slack.text_of(slack.posts.first)).to end_with("Answered in the control room.")
      expect(kept).to be_empty
    end

    it "is asked afresh if it comes back before the grace is up" do
      round
      later(described_class::GRACE - 1)
      round(question)
      later(described_class::GRACE)
      round(question)

      expect(slack.posts.size).to eq(1)
      expect(kept.size).to eq(1)
    end

    it "leaves an answered poll saying who answered it" do
      slack.click(slack.posts.first, "one")
      round(question)
      round
      later(described_class::GRACE)
      round

      expect(slack.text_of(slack.posts.first)).to include("Answered by <@UDANA>")
      expect(kept).to be_empty
    end
  end

  it "asks again when the engine did not take the answer" do
    round(question)
    slack.click(slack.posts.first, "one")
    round(question)
    later(described_class::REFUSED_AFTER + 1)
    2.times { round(question) }

    expect(slack.posts.size).to eq(2)
    expect(slack.text_of(slack.posts.first)).to end_with("asked again below.")
    expect(slack.text_of(slack.posts.last)).to include("React with a number")
  end

  it "does not post a second message when the ballot fails after the post" do
    slack.refuse("reactions.add", "missing_scope")
    bridge.offer(snapshot(question))
    expect { bridge.cycle }.to raise_error(OpenLanes::Error, /missing_scope; add the scope/)

    slack.allow("reactions.add")
    round(question)

    expect(slack.posts.size).to eq(1)
    expect(slack.called("reactions.add").last(2).map { it["name"] }).to eq(%w[one two])
  end

  # One poll Slack refuses must not hold up the others (the review's 🛑):
  # a message deleted by a person, a channel archived since, or a refusal
  # of that one message.
  describe "a poll Slack refuses" do
    let(:other) { question.merge(id: "041.00/B2", heading: "B2 — Which database?", options:) }
    let(:first) { slack.posts.first }
    let(:second) { slack.posts.last }

    before { round(question, other) }

    it "still hears the others once its message is deleted and its question settled elsewhere" do
      slack.delete(first)
      round(other)
      later(described_class::GRACE)
      slack.click(second, "two")
      4.times { round(other) }

      expect(queued.map { it.dig("payload", "question") }).to eq(["B2"])
      expect(kept.keys).to all(end_with(OpenLanes::Slack::Poll.new(plan: {}, question: other.transform_keys(&:to_s)).key.split("#").last))
      expect(OpenLanes::UI).to have_received(:log).with(%r{poll 041\.00/B1#\h+ is gone from Slack \(message_not_found\)}, level: :warn)
    end

    it "posts a deleted poll afresh while its question is still asked, and does not lose it to a restart" do
      slack.delete(first)
      3.times { round(question, other) }

      expect(slack.posts.size).to eq(2)
      expect(kept.size).to eq(2)
      expect(slack.posts).not_to include(first)
    end

    it "keeps reading the others while one redraw keeps failing, and says so once" do
      slack.refuse_at(first, "cant_update_message")
      slack.click(second, "one")
      4.times { round(question.merge(body: "Rewritten."), other) }

      expect(queued.map { it.dig("payload", "question") }).to eq(["B2"])
      expect(kept.size).to eq(2)
      expect(OpenLanes::UI).to have_received(:log).with(/poll .* skipped this cycle: .*cant_update_message/, level: :warn).once
    end

    it "forgets a poll whose channel was archived when it comes to close it" do
      slack.refuse_at(first, "is_archived")
      round(other)
      later(described_class::GRACE)
      round(other)

      expect(kept.size).to eq(1)
    end

    it "still ends the cycle on a refusal that holds for every poll" do
      slack.refuse("conversations.replies", "not_in_channel")

      expect { bridge.cycle }.to raise_error(OpenLanes::Slack::API::Refused, /not_in_channel/)
    end
  end

  describe "across a restart" do
    let(:second) { described_class.new(room:, outbox: OpenLanes::Slack::Outbox.new(store:, keys:), interval: 3600, clock: -> { now }) }

    after { second.stop }

    it "takes back the polls the last engine left open rather than posting them again" do
      round(question)
      second.start
      second.offer(snapshot(question))
      second.cycle

      expect(slack.posts.size).to eq(1)
    end

    it "says so when they cannot be read back" do
      allow(store).to receive(:hgetall).and_raise(OpenLanes::Live::Unavailable, "redis is gone")
      second.start

      expect(OpenLanes::UI).to have_received(:log).with(/open polls not read back \(redis is gone\)/, level: :warn)
    end
  end

  describe "when Redis is away" do
    it "keeps what it has to write until Redis is back" do
      bridge.offer(snapshot(question))
      bridge.cycle
      allow(store).to receive(:hset).and_raise(OpenLanes::Live::Unavailable, "gone")
      bridge.call
      allow(store).to receive(:hset).and_call_original
      bridge.call

      expect(kept.size).to eq(1)
    end

    it "takes a snapshot that was not published as no news about the questions" do
      round(question)
      bridge.offer(nil)
      later(described_class::GRACE)
      bridge.cycle

      expect(slack.text_of(slack.posts.first)).to include("React with a number")
    end
  end

  describe "the worker's pace" do
    before { bridge.offer(snapshot(question)) }

    it "is the interval when Slack answers" do
      expect(bridge.send(:pace)).to eq(OpenLanes::Slack::DEFAULT_INTERVAL)
    end

    it "is what Slack asks for when it is rate limited" do
      allow(room).to receive(:post).and_raise(OpenLanes::Slack::API::RateLimited.new(17))

      expect(bridge.send(:pace)).to eq(17)
    end

    it "backs off after a failure and says why once, not on every retry" do
      slack.refuse("chat.postMessage", "not_in_channel")

      expect(Array.new(3) { bridge.send(:pace) }).to all(eq(described_class::BACKOFF))
      expect(OpenLanes::UI).to have_received(:log).with(/slack: .*not_in_channel.*stay answerable in the control room/, level: :warn).once
    end

    it "says it again when it fails anew after working" do
      slack.refuse("chat.postMessage", "not_in_channel")
      bridge.send(:pace)
      slack.allow("chat.postMessage")
      bridge.send(:pace)
      slack.refuse("conversations.replies", "not_in_channel")
      bridge.send(:pace)

      expect(OpenLanes::UI).to have_received(:log).with(/not_in_channel/, level: :warn).twice
    end
  end

  it "runs on a thread of its own from start to stop" do
    fast = described_class.new(room:, outbox: OpenLanes::Slack::Outbox.new(store:, keys:), interval: 0.01)
    fast.offer(snapshot(question))
    fast.start
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    sleep(0.01) until slack.posts.any? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    fast.stop

    expect(slack.posts.size).to eq(1)
  end

  it "does not queue an answer the engine could not read as a command" do
    round(question.merge(id: "not an ordinal/B1"))
    slack.click(slack.posts.first, "one")
    bridge.offer(snapshot(question.merge(id: "not an ordinal/B1")))
    bridge.cycle
    allow(OpenLanes::Live).to receive(:enqueue).and_raise(OpenLanes::Live::Command::Invalid, "answer needs a plan")
    bridge.call

    expect(OpenLanes::UI).to have_received(:log).with("slack: answer not queued: answer needs a plan", level: :warn)
  end
end
