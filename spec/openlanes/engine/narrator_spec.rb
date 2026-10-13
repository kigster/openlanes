# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Narrator do
  subject(:narrator) { described_class.new(stream:, clock: -> { Time.new(2026, 10, 13, 13, 39, 10) }) }

  let(:stream) { StringIO.new }
  let(:lines) { stream.string.lines(chomp: true) }

  describe "#render" do
    it "keeps only the fields a line has, in the order a person reads them" do
      expect(narrator.render("started", plan: "003.00", status: "⭐️ Planned", agent: "yoda-writer", round: "01"))
        .to eq("003.00 ⭐️  Planned  yoda-writer r01  started")
    end

    # The log file's columns, echoed to the terminal, drew this line as a
    # row of empty cells with the message at the far end.
    it "draws an event with no plan as the message alone" do
      expect(narrator.render("idle: waiting for answers on 000.00, 001.00", pid: 83_054))
        .to eq("idle: waiting for answers on 000.00, 001.00")
    end

    it "names the state a plan moved to" do
      expect(narrator.render("finished: completed", plan: "003.00", to: "🟡 Building"))
        .to eq("003.00  finished: completed → 🟡  Building")
    end

    # Many fonts draw a colour emoji wider than its two cells; one space
    # after it let "🟡Building" and "🔴Changes" run together.
    it "fits each emoji to two cells and puts two spaces before its label" do
      expect(narrator.render("started", plan: "002.00", status: "⚪️ New", agent: "leah-researcher", round: "01", to: "🔴 Changes Requested"))
        .to eq("002.00 ⚪️  New  leah-researcher r01  started → 🔴  Changes Requested")
    end

    it "passes a status with no label through as it is" do
      expect(described_class.status_cell("🟡")).to eq("🟡")
    end

    it "takes out what would move the cursor: a carriage return, an escape, a newline" do
      expect(narrator.render("working\rOVER\e[2Kwritten\nhere")).to eq("working OVER written here")
    end
  end

  describe "#call" do
    it "writes one timestamped line per event" do
      narrator.call("started", { plan: "003.00", agent: "yoda-writer" })

      expect(lines).to eq(["13:39:10  003.00  yoda-writer  started"])
    end

    it "says a repeated event once, and again once something else was said" do
      2.times { narrator.call("idle: nothing to do", {}) }
      narrator.call("started", { plan: "003.00" })
      narrator.call("idle: nothing to do", {})

      expect(lines.map { it.split("  ", 2).last }).to eq(["idle: nothing to do", "003.00  started", "idle: nothing to do"])
    end

    it "keeps lines whole when several threads log at once" do
      Array.new(8) { |i| Thread.new { 25.times { |n| narrator.call("event #{i}-#{n}", { plan: "00#{i}.00" }) } } }.each(&:join)

      expect(lines).to all(match(/\A13:39:10  00\d\.00  event \d-\d+\z/))
    end

    it "never raises into the thread that logged" do
      broken = described_class.new(stream: Object.new)

      expect { broken.call("started", {}) }.not_to raise_error
    end

    it "hears UI.log once tapped, fields the file does not take included" do
      tap = OpenLanes::UI.tap_log(narrator)
      OpenLanes::UI.log("finished: ok", plan: "003.00", to: "🟡 Building")
      OpenLanes::UI.untap_log(tap)

      expect(lines).to eq(["13:39:10  003.00  finished: ok → 🟡  Building"])
    end
  end
end
