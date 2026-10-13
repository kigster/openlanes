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
end
