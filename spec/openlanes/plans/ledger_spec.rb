# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::Ledger do
  let(:document) do
    <<~MARKDOWN
      # A Feature

      ## Research

      > [!NOTE]
      >
      > [2026-09-04 11:29:20 AM PDT] [ agent: leah-researcher   status: Started, round 1 ]

      What was found.

      > [!NOTE]
      >
      > [2026-09-04 11:44:03 AM PDT] [ agent: leah-researcher   status: Completed, round 1 ]
      > [2026-09-04 11:44:04 AM PDT] [ next: yoda-writer ]
    MARKDOWN
  end

  describe ".parse" do
    subject(:reading) { described_class.parse(document, file: "spec.md") }

    it "reads every entry in document order, with its file and line" do
      expect(reading.entries.map { |e| [e.agent, e.status, e.round, e.line] })
        .to eq([["leah-researcher", "Started", 1, 7], ["leah-researcher", "Completed", 1, 13]])
      expect(reading.entries.map(&:file).uniq).to eq(["spec.md"])
    end

    it "reads the handoff as its own kind of line" do
      expect(reading.handoffs.map { |h| [h.next, h.line] }).to eq([["yoda-writer", 14]])
    end

    it "parses the timestamp into a Time" do
      expect(reading.entries.first.at).to be_a(Time)
      expect(reading.entries.first.at.hour).to eq(11)
    end

    it "keeps a parenthesised note" do
      text = "> [2026-09-04 11:44:03 AM PDT] [ agent: hansolo-reviewer   status: Completed, round 2 (rejected 1/2) ]"
      entry = described_class.parse(text, file: "pull-requests.md").entries.first
      expect(entry.note).to eq("rejected 1/2")
    end

    it "accepts a bold status, and says the entry was bold" do
      text = "> [2026-09-04 11:52:07 AM PDT] [ agent: leah-researcher   status: **Interrupted, round 1 (killed by harness after 15s grace)** ]"
      entry = described_class.parse(text, file: "spec.md").entries.first
      aggregate_failures do
        expect(entry.status).to eq("Interrupted")
        expect(entry.note).to eq("killed by harness after 15s grace")
        expect(entry.bold).to be(true)
      end
    end

    # A closed vocabulary. A verb outside it is an error to show, not a
    # line to skip: an agent that writes "Done" has said nothing the
    # harness can act on, and silence here would look like a stall.
    it "reports a line that tries to be an entry and fails as a problem, not as nothing" do
      text = "> [2026-09-04 11:44:03 AM PDT] [ agent: leah-researcher   status: Done, round 1 ]"
      reading = described_class.parse(text, file: "spec.md")
      aggregate_failures do
        expect(reading.entries).to be_empty
        expect(reading.problems.map { |p| [p.file, p.line] }).to eq([["spec.md", 1]])
      end
    end

    it "ignores ordinary blockquotes" do
      reading = described_class.parse("> just a quote\n> [!NOTE]\n> another", file: "spec.md")
      expect(reading.entries + reading.handoffs + reading.problems).to be_empty
    end
  end

  describe ".read", :tree do
    it "reads the files in the order given and skips the ones that do not exist" do
      path = plans { |t| t.plan "001.00", :new, "x", files: { "spec.md" => document } }
      dir = File.join(path, "001.00━━⚪━━❯x")
      reading = described_class.read(dir, %w[plan-backend.md spec.md])
      expect(reading.entries.map(&:file).uniq).to eq(["spec.md"])
    end
  end

  describe ".last_for" do
    it "returns the agent's latest entry by timestamp, then by file order, then by line" do
      early = "> [2026-09-04 11:00:00 AM PDT] [ agent: luke-backend   status: Completed, round 1 ]"
      late = "> [2026-09-04 11:30:00 AM PDT] [ agent: luke-backend   status: Started, round 1 ]"
      reading = described_class::Reading.new(
        entries:  described_class.parse(late, file: "pull-requests.md").entries +
          described_class.parse(early, file: "plan-backend.md").entries,
        handoffs: [],
        problems: []
      )
      expect(described_class.last_for(reading, "luke-backend").status).to eq("Started")
    end

    it "is nil for an agent that never wrote" do
      reading = described_class.parse(document, file: "spec.md")
      expect(described_class.last_for(reading, "yoda-writer")).to be_nil
    end
  end

  describe ".handoff_after" do
    it "finds the next: line directly after a Completed entry in the same file" do
      reading = described_class.parse(document, file: "spec.md")
      completed = reading.entries.last
      expect(described_class.handoff_after(reading, completed).next).to eq("yoda-writer")
    end

    it "does not attach a next: line that follows a different entry" do
      text = <<~MD
        > [2026-09-04 11:44:03 AM PDT] [ agent: leah-researcher   status: Completed, round 1 ]
        > [2026-09-04 11:50:00 AM PDT] [ agent: yoda-writer   status: Started, round 1 ]
        > [2026-09-04 11:50:01 AM PDT] [ next: luthen-rael-planner ]
      MD
      reading = described_class.parse(text, file: "spec.md")
      expect(described_class.handoff_after(reading, reading.entries.first)).to be_nil
    end
  end

  describe ".render and .block" do
    it "round-trips an entry through the parser" do
      entry = described_class::Entry.new(at: Time.new(2026, 9, 4, 11, 29, 20),
        agent: "leah-researcher",
        status: "Started",
        round: 1,
        note: nil,
        file: "spec.md",
        line: 0,
        bold: false)
      text = described_class.render(entry)
      back = described_class.parse(text, file: "spec.md").entries.first
      expect(back.with(file: "spec.md", line: 1, at: back.at)).to eq(entry.with(line: 1, at: back.at))
      expect(text).to start_with("> [2026-09-04 11:29:20 AM ")
    end

    it "wraps lines in a NOTE alert with the blank quote line GitHub wants" do
      expect(described_class.block("> a", "> b")).to eq("> [!NOTE]\n>\n> a\n> b\n")
    end
  end

  describe ".append", :tree do
    it "appends a NOTE block, separated by a blank line, creating the file when missing" do
      path = File.join(plans_root, "pull-requests.md")
      described_class.append(path, "> one")
      described_class.append(path, "> two")
      expect(File.read(path)).to eq("> [!NOTE]\n>\n> one\n\n> [!NOTE]\n>\n> two\n")
    end
  end

  describe ".stripped" do
    it "removes ledger blocks so a document can be judged by what it says" do
      expect(described_class.stripped(document)).not_to include("[ agent:")
      expect(described_class.stripped(document)).to include("What was found.")
    end
  end
end
