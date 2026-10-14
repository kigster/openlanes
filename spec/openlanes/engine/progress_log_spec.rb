# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::ProgressLog do
  # A fixed clock, so the timestamp column is an assertion rather than a race.
  let(:at) { Time.new(2026, 8, 23, 16, 22, 14) }

  # Everything up to and including the closing bracket: the part that must be
  # the same width on every line.
  def prefix_of(line) = line[0..line.index("]")]

  describe ".render" do
    it "lays every field out in its own column" do
      line = described_class.render(
        "editing spec.md",
        plan:    "003.00",
        status:  "⭐️ Planned",
        agent:   "yoda-writer",
        seconds: 42,
        round:   "01",
        pid:     91_234,
        at:
      )

      expect(line).to eq(
        "[16:22:14 | 003.00 | ⭐️  Planned            | yoda-writer          | 01 |   91234 |    42s] editing spec.md"
      )
    end

    it "matches the line the module's @example documents" do
      source = File.read(File.expand_path("../../../lib/openlanes/engine/progress_log.rb", __dir__))
      documented = source[/^\s*#\s+#=> "(.*)"$/, 1]
      line = described_class.render(
        "editing spec.md",
        plan:    "003.00",
        status:  "⭐️ Planned",
        agent:   "yoda-writer",
        seconds: 42,
        round:   "01",
        pid:     91_234,
        at:
      )

      expect(documented).to eq(line)
    end

    it "returns one line, with no trailing newline" do
      line = described_class.render("editing spec.md", at:)

      expect(line).not_to include("\n")
    end

    it "holds every column open when a round header has nothing to put in them" do
      header = described_class.render("round 1 - 3 plans", pid: 91_234, at:)
      full = described_class.render(
        "editing spec.md",
        plan:    "003.00",
        status:  "⭐️ Planned",
        agent:   "yoda-writer",
        seconds: 42,
        round:   "01",
        pid:     91_234,
        at:
      )

      aggregate_failures do
        expect(header).to eq("[16:22:14 |        |                        |                      |    |   91234 |       ] round 1 - 3 plans")
        expect(OpenLanes::UI.display_width(prefix_of(header))).to eq(OpenLanes::UI.display_width(prefix_of(full)))
        expect(OpenLanes::UI.display_width(prefix_of(header))).to eq(described_class::LINE_WIDTH)
      end
    end

    it "defaults the process id to this process and the clock to now" do
      line = described_class.render("started")

      expect(line).to include(Process.pid.to_s)
    end

    it "cuts a name too long for its column rather than pushing the columns out" do
      line = described_class.render("x", agent: "a-very-long-agent-name-indeed", at:)

      aggregate_failures do
        expect(line).to include("| a-very-long-agent-na |")
        expect(OpenLanes::UI.display_width(prefix_of(line))).to eq(described_class::LINE_WIDTH)
      end
    end

    it "lands the separator after an emoji status in the same column as one without" do
      # The point of padding by display cells: "💩" is one character and two
      # cells, "Planned" is seven of each. Counting characters drifts by one
      # per emoji; counting cells does not.
      emoji = described_class.render("x", status: "💩 Scrapped by Review", at:)
      plain = described_class.render("x", status: "Planned", at:)

      aggregate_failures do
        expect(OpenLanes::UI.display_width(prefix_of(emoji))).to eq(described_class::LINE_WIDTH)
        expect(OpenLanes::UI.display_width(prefix_of(plain))).to eq(described_class::LINE_WIDTH)
        expect(emoji.index("|", emoji.index("💩"))).not_to eq(plain.index("|", plain.index("Planned")))
        expect(OpenLanes::UI.display_width(emoji[0...emoji.index("|", emoji.index("💩"))])).to eq(OpenLanes::UI.display_width(plain[0...plain.index("|", plain.index("Planned"))]))
      end
    end

    it "renders seconds as a whole number, right justified, with a trailing s" do
      aggregate_failures do
        expect(described_class.render("x", seconds: 42, at:)).to include("|    42s]")
        expect(described_class.render("x", seconds: 907.4, at:)).to include("|   907s]")
        expect(described_class.render("x", seconds: 41.6, at:)).to include("|    42s]")
        expect(described_class.render("x", seconds: 0, at:)).to include("|     0s]")
        expect(described_class.render("x", at:)).to include("|       ]")
      end
    end

    it "drops the separating space when there is no message" do
      expect(described_class.render("", pid: 91_234, at:)).to end_with("|       ]")
    end
  end

  describe "the column widths" do
    it "fits the widest state the machine defines, label in full" do
      widest = OpenLanes::Plans::STATUSES.map { |status| OpenLanes::UI.display_width(status.label) }.max

      expect(described_class::STATUS_WIDTH).to eq(2 + 2 + widest)
    end

    it "leaves two spaces between a status's emoji and its label" do
      line = described_class.render("x", status: "🔴 Changes Requested", at: Time.local(2026, 10, 13, 14, 24, 11))

      expect(line).to include("| 🔴  Changes Requested ")
    end

    it "fits the longest specialist name on disk" do
      longest = OpenLanes::Agents::Registry.new.all.map { |agent| agent.name.length }.max

      expect(described_class::AGENT_WIDTH).to be > longest
    end
  end
end
