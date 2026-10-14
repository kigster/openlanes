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

  it "carries on with the tick when Redis goes away" do
    allow(mail).to receive(:drain).and_raise(OpenLanes::Live::Unavailable, "Redis at memory:// is unavailable")

    expect { dispatcher.tick }.not_to raise_error
  end

  it "drains nothing without Redis, which costs nothing because send wrote the file" do
    dispatcher.mail = nil
    published(5)
    dispatcher.tick

    expect(numbers).to eq([])
  end
end
