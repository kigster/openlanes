# frozen_string_literal: true

require_relative "../live/live_context"

# The harness as the writer of drained mail (plan 003, B4): a message that
# reached Redis is kept in the plan's `state.json` once, however many ticks
# see it, and one `mail send` already wrote there is not written twice.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  let(:mail) { OpenLanes::Live::Mail.new(store:, keys:) }
  let(:folder) { path_of("001.00") }
  let(:numbers) { OpenLanes::Plans::PlanState.for(folder).messages.map { it["number"] } }

  def published(number, body = "contract is up")
    mail.publish(plan: "001.00",
      message: { "number" => number, "at" => "2026-10-13T19:17:10-07:00", "from" => "luke-backend", "to" => "rey-frontend", "body" => body })
  end

  before do
    building("001.00", "tax-rule-dsl")
    dispatcher.mail = mail
    start_agents
  end

  it "keeps a message that only Redis had, once, however many ticks drain" do
    published(5)
    3.times { dispatcher.tick }

    aggregate_failures do
      expect(numbers).to eq([5])
      expect(OpenLanes::Plans.mailbox(folder).for("rey-frontend").map(&:body)).to eq(["contract is up"])
    end
  end

  it "writes nothing for a message mail send already put in state.json" do
    sent = OpenLanes::Plans.mailbox(folder).append(from: "luke-backend", to: "rey-frontend", body: "contract is up")
    mail.publish(plan: "001.00", message: sent)
    before = File.mtime(File.join(folder, "state.json"))
    dispatcher.tick

    aggregate_failures do
      expect(numbers).to eq([1])
      expect(File.mtime(File.join(folder, "state.json"))).to eq(before)
    end
  end

  it "leaves out a message the plan cannot keep, and keeps the rest" do
    published(6, " ")
    published(7)
    dispatcher.tick

    expect(numbers).to eq([7])
  end

  # A worktree's `mail send` reaches the main checkout only through the
  # stream, and the stream forgets it after an hour, so the drain cannot
  # wait for an agent to run on the plan.
  it "keeps mail for a plan with nobody running on it" do
    building("002.00", "idle-plan")
    mail.publish(plan: "002.00",
      message: { "number" => 1, "at" => "2026-10-13T19:17:10-07:00", "from" => "luke-backend", "to" => "rey-frontend", "body" => "hi" })
    dispatcher.tick

    expect(OpenLanes::Plans::PlanState.for(path_of("002.00")).messages.map { it["body"] }).to eq(["hi"])
  end

  it "leaves a message pending while its plan cannot be found, and keeps it once it can" do
    mail.publish(plan: "002.00",
      message: { "number" => 1, "at" => "2026-10-13T19:17:10-07:00", "from" => "luke-backend", "to" => "rey-frontend", "body" => "hi" })
    dispatcher.tick

    aggregate_failures do
      expect(store.xreadgroup(keys.mail, keys.mail_group("002.00"), "harness", id: "0").size).to eq(1)
      building("002.00", "late-plan")
      dispatcher.tick
      expect(OpenLanes::Plans::PlanState.for(path_of("002.00")).messages.map { it["body"] }).to eq(["hi"])
      expect(store.xreadgroup(keys.mail, keys.mail_group("002.00"), "harness", id: "0")).to eq([])
    end
  end

  it "carries on with the tick when Redis goes away" do
    allow(mail).to receive(:plans_since).and_raise(OpenLanes::Live::Unavailable, "Redis at memory:// is unavailable")

    expect { dispatcher.tick }.not_to raise_error
  end

  it "drains nothing without Redis, which costs nothing because send wrote the file" do
    dispatcher.mail = nil
    published(5)
    dispatcher.tick

    expect(numbers).to eq([])
  end
end
