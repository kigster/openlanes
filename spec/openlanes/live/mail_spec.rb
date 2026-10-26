# frozen_string_literal: true

RSpec.describe OpenLanes::Live::Mail do
  subject(:mail) { described_class.new(store:, keys:) }

  let(:store) { OpenLanes::Live::MemoryStore.new }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "n1:c1") }
  let(:message) do
    OpenLanes::Plans::Mailbox::Message.new(number: 7,
      at: "2026-10-13 19:17:10 -0700",
      from: "backend-coder",
      to: "frontend-coder",
      body: "GET /returns/:id is up")
  end

  it "keeps one stream per checkout, the plan riding inside each entry" do
    mail.publish(plan: "003.00", message:)

    aggregate_failures do
      expect(keys.mail).to eq("openlanes:github.com/acme/widgets:n1:c1:mail")
      expect(JSON.parse(store.xrange(keys.mail).first.fields["json"])["plan"]).to eq("003.00")
    end
  end

  it "drains what was published for the plan, as state.json holds it, once" do
    mail.publish(plan: "003.00", message:)

    aggregate_failures do
      expect(mail.drain(plan: "003.00", consumer: "frontend-coder"))
        .to eq([{ "number" => 7, "at" => "2026-10-13T19:17:10-07:00", "from" => "backend-coder",
                  "to" => "frontend-coder", "body" => "GET /returns/:id is up", "read" => "no" }])
      expect(mail.drain(plan: "003.00", consumer: "frontend-coder")).to eq([])
    end
  end

  it "acks what it delivered, so nothing is left pending" do
    mail.publish(plan: "003.00", message:)
    mail.drain(plan: "003.00", consumer: "frontend-coder")

    expect(store.xreadgroup(keys.mail, keys.mail_group("003.00"), "frontend-coder", id: "0")).to eq([])
  end

  it "acks only what the block kept, and offers the rest again on the next drain" do
    mail.publish(plan: "003.00", message:)
    mail.publish(plan: "003.00", message: message.with(number: 8))

    aggregate_failures do
      expect(mail.drain(plan: "003.00", consumer: "harness") { it["number"] == 7 }.map { it["number"] }).to eq([8])
      expect { mail.drain(plan: "003.00", consumer: "harness") { raise "disk full" } }.to raise_error("disk full")
      expect(mail.drain(plan: "003.00", consumer: "harness") { true }).to eq([])
      expect(store.xreadgroup(keys.mail, keys.mail_group("003.00"), "harness", id: "0")).to eq([])
    end
  end

  it "names the plans the stream has mail for, from a cursor on" do
    mail.publish(plan: "003.00", message:)
    mail.publish(plan: "004.00", message:)
    plans, cursor = mail.plans_since("0")
    mail.publish(plan: "005.00", message:)

    aggregate_failures do
      expect(plans).to eq(%w[003.00 004.00])
      expect(mail.plans_since(cursor).first).to eq(%w[005.00])
    end
  end

  it "leaves another plan's messages for that plan's own drain" do
    mail.publish(plan: "004.00", message:)

    aggregate_failures do
      expect(mail.drain(plan: "003.00", consumer: "backend-coder")).to eq([])
      expect(mail.drain(plan: "004.00", consumer: "backend-coder").map { it["number"] }).to eq([7])
    end
  end

  it "accepts a message as a Hash, with a Time for when" do
    mail.publish(plan: "003.00", message: { number: 2, at: Time.utc(2026, 10, 13, 12), from: "a", to: "b", body: "hi" })

    expect(mail.drain(plan: "003.00", consumer: "b").first).to include("number" => 2, "at" => "2026-10-13T12:00:00Z")
  end

  it "passes on a when it cannot read, rather than dropping the message" do
    mail.publish(plan: "003.00", message: { number: 3, at: "sometime", from: "a", to: "b", body: "hi" })

    expect(mail.drain(plan: "003.00", consumer: "b").first["at"]).to eq("sometime")
  end

  it "skips an entry that is not a message" do
    store.xadd(keys.mail, { json: "not json" })
    store.xadd(keys.mail, { json: "[1]" })

    expect(mail.drain(plan: "003.00", consumer: "b")).to eq([])
  end

  it "expires the stream an hour after the last publish" do
    mail.publish(plan: "003.00", message:)

    expect(store.ttl(keys.mail)).to be_between(OpenLanes::Live::Keys::MAIL_TTL - 1, OpenLanes::Live::Keys::MAIL_TTL)
  end

  it "gives a stream that a drain made an expiry too, so an idle plan leaves nothing behind" do
    mail.drain(plan: "003.00", consumer: "b")

    expect(store.ttl(keys.mail)).to be > 0
  end

  it "trims what is older than an hour on each publish" do
    # The store takes entry ids from the wall clock, so the old entry is
    # written an hour and a minute ago.
    allow(Time).to receive(:now).and_return(Time.now - OpenLanes::Live::Keys::MAIL_TTL - 60)
    mail.publish(plan: "003.00", message:)
    allow(Time).to receive(:now).and_call_original
    mail.publish(plan: "003.00", message: message.with(number: 8))

    expect(store.xrange(keys.mail).map { JSON.parse(it.fields["json"]).dig("message", "number") }).to eq([8])
  end
end
