# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::Mailbox, :tree do
  subject(:mailbox) { described_class.new(dir: folder) }

  let(:folder) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "paired", files: { "spec.md" => spec_body, "plan.md" => "# P" } }
    path
  end

  def luke_to_rey(body) = mailbox.append(from: "luke-backend", to: "rey-frontend", body:)

  def rey_to_luke(body) = mailbox.append(from: "rey-frontend", to: "luke-backend", body:)

  it "is empty before anybody has written" do
    aggregate_failures do
      expect(mailbox).not_to exist
      expect(mailbox.messages).to be_empty
      expect(mailbox.for("luke-backend")).to be_empty
    end
  end

  it "numbers messages from one, in the order they were written" do
    luke_to_rey("The endpoint is up.")
    rey_to_luke("Seen; wiring the screen.")

    expect(mailbox.messages.map { |m| [m.number, m.from, m.to] })
      .to eq([[1, "luke-backend", "rey-frontend"], [2, "rey-frontend", "luke-backend"]])
  end

  it "keeps messages in the plan's state.json" do
    luke_to_rey("first")
    luke_to_rey("second")

    expect(OpenLanes::Plans::PlanState.for(folder).messages.map { |m| [m["number"], m["body"]] })
      .to eq([[1, "first"], [2, "second"]])
  end

  it "writes no mailbox.md any more" do
    luke_to_rey("first")
    expect(File.exist?(File.join(folder, "mailbox.md"))).to be(false)
  end

  context "with messages from before state.json, in mailbox.md" do
    before do
      File.write(File.join(folder, "mailbox.md"),
        "# Mailbox\n\n## 1 · 2026-09-06 10:30:53 -0700 · luke-backend → rey-frontend\n\nold news\n")
    end

    it "still reads them, and numbers new messages after them" do
      luke_to_rey("new news")
      expect(mailbox.messages.map { |m| [m.number, m.body] }).to eq([[1, "old news"], [2, "new news"]])
    end
  end

  # A message is prose. It may carry paragraphs, a heading of its own and
  # code, and all of it has to come back as written or the reader acts on
  # half a sentence.
  it "parses back exactly what it wrote, paragraphs and headings included" do
    body = "Two things.\n\n## Not a message heading\n\n    curl -s /returns/1\n\nThat is all."
    written = luke_to_rey(body)

    read = mailbox.messages.first
    aggregate_failures do
      expect(read).to eq(written)
      expect(read.body).to eq(body)
      expect(read.at).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}\z/)
    end
  end

  it "answers a reader with only the messages addressed to them" do
    luke_to_rey("for rey")
    rey_to_luke("for luke")
    luke_to_rey("for rey again")

    expect(mailbox.for("rey-frontend").map(&:body)).to eq(["for rey", "for rey again"])
  end

  it "skips what a reader says they have already seen" do
    luke_to_rey("one")
    luke_to_rey("two")
    luke_to_rey("three")

    expect(mailbox.for("rey-frontend", after: 2).map(&:body)).to eq(["three"])
  end

  describe "a command's message, appended twice" do
    let!(:first) { mailbox.append(from: "human", to: "luke-backend", body: "hi", command: "01JM") }
    let!(:again) { mailbox.append(from: "human", to: "luke-backend", body: "hi", command: "01JM") }

    it "is there once, and the second append answers with the first" do
      expect([mailbox.messages.size, again]).to eq([1, first])
    end
  end

  it "refuses a message with nothing in it" do
    expect { luke_to_rey("   \n") }.to raise_error(OpenLanes::Error, /body/)
  end

  # `dry-cli` does not enforce `required:` on an option, so a send typed
  # without `--to` reached here with nil. The entry it wrote had an empty
  # recipient, which the heading parser could never read back: written,
  # numbered, and invisible to everybody.
  it "refuses a sender or recipient the heading could not carry" do
    aggregate_failures do
      expect { mailbox.append(from: "luke-backend", to: nil, body: "x") }.to raise_error(OpenLanes::Error, /--to/)
      expect { mailbox.append(from: "", to: "rey-frontend", body: "x") }.to raise_error(OpenLanes::Error, /--from/)
      expect { mailbox.append(from: "luke backend", to: "rey-frontend", body: "x") }.to raise_error(OpenLanes::Error)
      expect(mailbox).not_to exist
    end
  end

  # Both halves finish units at their own pace and write when they do. Two
  # appends landing in the same instant used to be able to read the same
  # last number, and one message then carried the other's number.
  it "keeps every message when both halves write at once" do
    writers = %w[luke-backend rey-frontend].map do |name|
      Thread.new do
        20.times { |i| mailbox.append(from: name, to: "other", body: "#{name} #{i}") }
      end
    end
    writers.each(&:join)

    messages = mailbox.messages
    aggregate_failures do
      expect(messages.size).to eq(40)
      expect(messages.map(&:number)).to eq((1..40).to_a)
      expect(messages.map(&:body).uniq.size).to eq(40)
    end
  end

  describe "read receipts" do
    it "writes a new message unread" do
      luke_to_rey("first")

      aggregate_failures do
        expect(mailbox.messages.first.read).to eq("no")
        expect(OpenLanes::Plans::PlanState.for(folder).messages.first["read"]).to eq("no")
      end
    end

    it "flips only the message its reader acks" do
      luke_to_rey("first")
      luke_to_rey("second")
      mailbox.ack(2, by: "rey-frontend")

      expect(mailbox.messages.map { |m| [m.number, m.read] }).to eq([[1, "no"], [2, "yes"]])
    end

    it "acks an already-read message without complaint" do
      luke_to_rey("first")
      mailbox.ack(1, by: "rey-frontend")

      expect(mailbox.ack("1", by: "rey-frontend")).to be_read
    end

    it "counts a message written before acks existed as unacked" do
      OpenLanes::Plans::PlanState.for(folder).update do |data|
        data["messages"] << { "number" => 1, "at" => Time.now.iso8601, "from" => "luke-backend", "to" => "rey-frontend", "body" => "old" }
      end

      aggregate_failures do
        expect(mailbox.messages.first).not_to be_read
        expect(mailbox.unacked).to eq(1)
      end
    end

    it "counts unacked mail for everybody or for one reader" do
      luke_to_rey("one")
      luke_to_rey("two")
      rey_to_luke("three")
      mailbox.ack(1, by: "rey-frontend")

      aggregate_failures do
        expect(mailbox.unacked).to eq(2)
        expect(mailbox.unacked("rey-frontend")).to eq(1)
        expect(mailbox.unacked("luke-backend")).to eq(1)
      end
    end

    it "treats mailbox.md history as read, since nobody is left to ack it" do
      File.write(File.join(folder, "mailbox.md"), "## 1 · 2026-09-06 10:30:53 -0700 · luke-backend → rey-frontend\n\nold\n")

      aggregate_failures do
        expect(mailbox.unacked).to eq(0)
        expect(mailbox.ack(1, by: "rey-frontend")).to be_read
        expect { mailbox.ack(1, by: "luke-backend") }.to raise_error(OpenLanes::Error, /for rey-frontend/)
      end
    end

    it "refuses an unknown number, a non-number, and a reader the message was not for" do
      luke_to_rey("first")

      aggregate_failures do
        expect { mailbox.ack(9, by: "rey-frontend") }.to raise_error(OpenLanes::Error, /no message #9/)
        expect { mailbox.ack("x", by: "rey-frontend") }.to raise_error(OpenLanes::Error, /positive integer/)
        expect { mailbox.ack(1, by: "luke-backend") }.to raise_error(OpenLanes::Error, /for rey-frontend, not luke-backend/)
        expect(mailbox.messages.first).not_to be_read
      end
    end
  end

  describe "#render" do
    it "says so when there is nothing" do
      expect(mailbox.render).to include("No messages.")
    end

    it "prints every message with whether it was read" do
      luke_to_rey("The endpoint is up.")
      rey_to_luke("Seen.")
      mailbox.ack(1, by: "rey-frontend")

      aggregate_failures do
        expect(mailbox.render).to match(/## 1 · .+ · luke-backend → rey-frontend · read\n\nThe endpoint is up\./)
        expect(mailbox.render).to match(/## 2 · .+ · rey-frontend → luke-backend · unread\n\nSeen\./)
      end
    end
  end

  # What the harness keeps of a message drained from Redis (plan 003, B4).
  describe "#deliver" do
    let(:drained) do
      { "number" => 4, "at" => "2026-10-13T19:17:10-07:00", "from" => "luke-backend", "to" => "rey-frontend", "body" => "up",
        "read" => "yes" }
    end

    it "keeps it under its own number, unread whatever it arrived saying" do
      delivered = mailbox.deliver(drained)

      aggregate_failures do
        expect(delivered).to have_attributes(number: 4, body: "up", read: "no")
        expect(mailbox.deliver(drained)).to be_nil
        expect(mailbox.messages.map(&:number)).to eq([4])
      end
    end

    it "keeps them in number order whatever order they arrive in" do
      mailbox.deliver(drained)
      mailbox.deliver(drained.merge("number" => 2, "body" => "earlier"))

      expect(OpenLanes::Plans::PlanState.for(folder).messages.map { it["number"] }).to eq([2, 4])
    end

    it "skips a message mailbox.md already holds, recognised by what it says" do
      File.write(File.join(folder, "mailbox.md"), "## 4 · 2026-10-13 19:17:10 -0700 · luke-backend → rey-frontend\n\nup\n")

      aggregate_failures do
        expect(mailbox.deliver(drained)).to be_nil
        expect(OpenLanes::Plans::PlanState.for(folder).messages).to eq([])
      end
    end

    it "renumbers a different message whose number mailbox.md took" do
      File.write(File.join(folder, "mailbox.md"), "## 4 · 2026-09-06 10:30:53 -0700 · luke-backend → rey-frontend\n\nold\n")

      expect(mailbox.deliver(drained)).to have_attributes(number: 5, body: "up")
    end

    # A worktree's state.json and the main checkout's number independently,
    # so two different messages can both arrive as #4. The number is not
    # their identity; the id `mail send` writes is.
    it "keeps two different messages that both arrived as #4, as #4 and #5" do
      mailbox.deliver(drained.merge("id" => "a1"))
      mailbox.deliver(drained.merge("id" => "b2", "body" => "also up"))

      expect(mailbox.messages.map { [it.number, it.body, it.id] }).to eq([[4, "up", "a1"], [5, "also up", "b2"]])
    end

    it "keeps one message delivered twice once, by its id" do
      2.times { mailbox.deliver(drained.merge("id" => "a1")) }

      expect(mailbox.messages.map(&:number)).to eq([4])
    end

    it "takes one without an id as a copy of a message that says the same thing" do
      sent = mailbox.append(from: "luke-backend", to: "rey-frontend", body: "up", at: Time.new(2026, 10, 13, 19, 17, 10, "-07:00"))

      aggregate_failures do
        expect(sent.id).to match(/\A\h{8}-/)
        expect(mailbox.deliver(drained.merge("number" => 9))).to be_nil
        expect(mailbox.messages.map(&:number)).to eq([1])
      end
    end

    it "refuses one with no number, no body, or no single sender" do
      aggregate_failures do
        expect { mailbox.deliver(drained.merge("number" => "4")) }.to raise_error(OpenLanes::Error, /positive number/)
        expect { mailbox.deliver(drained.merge("body" => " ")) }.to raise_error(OpenLanes::Error, /body/)
        expect { mailbox.deliver(drained.merge("from" => "two words")) }.to raise_error(OpenLanes::Error, /one agent name/)
      end
    end
  end
end
