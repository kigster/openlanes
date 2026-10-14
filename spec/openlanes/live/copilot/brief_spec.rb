# frozen_string_literal: true

RSpec.describe OpenLanes::Live::Copilot::Brief do
  subject(:text) { described_class.new(text: "Why?", board:, others:, plans_dir: "/repo/.plans", trace_dir: "/tmp/traces").to_s }

  let(:others) { [] }
  let(:plan) do
    { "ordinal" => "003.00", "title" => "Ledger export", "status" => { "emoji" => "🟢", "label" => "Ready for review" },
      "lane" => "plan", "elapsed" => 1800, "cost" => 1.5, "pr" => { "number" => 41, "state" => "open" },
      "cars" => [], "questions" => [],
      "interrupted" => { "agent" => "rey-frontend", "at" => "2026-10-13T10:00:00Z", "note" => "left a resume note" } }
  end
  let(:board) do
    { "at" => "2026-10-13T10:05:00Z", "run" => { "status" => "idle" }, "plans" => [plan],
      "backlog" => [{ "ordinal" => "004.00", "title" => "Web room", "status" => { "label" => "New" } }],
      "log" => Array.new(30) { |i| { "at" => "t#{i}", "source" => "engine", "level" => "info", "text" => "line #{i}" } } }
  end

  it "names the plan, its pull request and its interruption" do
    expect(text).to include("003.00 Ledger export: 🟢 Ready for review, plan lane, 30m worked, $1.50, PR #41 open",
      "interrupted: rey-frontend at 2026-10-13T10:00:00Z: left a resume note")
  end

  it "lists the backlog" do
    expect(text).to include("Backlog: 004.00 Web room (New)")
  end

  it "carries only the newest log lines" do
    expect([text.include?("line 29"), text.include?("line 9\n")]).to eq([true, false])
  end

  it "says where to read further, and ends with the person's words" do
    expect(text).to include("Plan folders: /repo/.plans", "transcripts: /tmp/traces").and end_with("## The person says\n\nWhy?")
  end

  context "with other machines on the repository" do
    let(:others) { [{ "node" => { "user" => "sam", "host" => "mini" }, "plans" => [] }] }

    it "names them, read only" do
      expect(text).to include("## Other machines (read only)", "- sam@mini: no plans")
    end
  end

  context "with a long question" do
    let(:plan) do
      super().merge("questions" => [{ "id" => "003.00/B2", "owner" => "technical", "agent" => nil, "held" => true,
                                      "heading" => "B2 Keys", "body" => "word " * 200 }])
    end

    it "cuts its body and says who asked" do
      expect(text).to match(%r{question 003.00/B2 \(technical, asked by unknown, held\): B2 Keys: (word ){80}…})
    end
  end

  context "with nothing on the board" do
    let(:board) { { "at" => "now", "run" => {}, "plans" => [], "log" => [] } }

    it "says there are no plans" do
      expect(text).to include("No plans on this machine's board.")
    end
  end
end
