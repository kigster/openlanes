# frozen_string_literal: true

RSpec.describe OpenLanes::Events::Report do
  let(:fixtures) { File.expand_path("../../fixtures/events", __dir__) }
  let(:log) { OpenLanes::Events::Log.new(dir: fixtures) }
  let(:result) { OpenLanes::Events.report(log.events, skipped_lines: log.skipped_lines) }

  it "merges two node files, counting the duplicate once" do
    expect(log.files.size).to eq(2)
    expect(result.runs).to eq(3)
    expect(result.completion_rate).to eq(0.6667)
  end

  it "reports 3 blocks over 2 unique runs" do
    expect(result).to have_attributes(blocks: 3, runs_needing_feedback: 2, intervention_rate: 0.6667)
  end

  context "when one Blocked signing leaves B1, B2 and B3 open" do
    def event(id, kind, at, **payload)
      OpenLanes::Events::Event.new(event_id: id,
        kind:,
        at: Time.iso8601(at),
        plan: "001.00",
        run: "r1",
        agent: "luke-backend",
        payload: { "round" => 1 }.merge(payload))
    end

    let(:three) do
      [event("s", "agent_started", "2026-10-16T12:00:00Z"),
       event("b", "block_raised", "2026-10-16T12:10:00Z", "blocks" => 3),
       event("f", "agent_finished", "2026-10-16T12:11:00Z", "status" => "Blocked"),
       *(1..3).map { event("a#{it}", "human_answered", "2026-10-16T12:1#{it}:00Z", "block" => "B#{it}") }]
    end
    let(:result) { OpenLanes::Events.report(three) }

    it "counts three blocks on one run" do
      expect(result).to have_attributes(blocks: 3, runs_needing_feedback: 1)
    end

    it "pairs each of the three questions with its own answer" do
      expect(result.time_to_answer).to eq(count: 3, median_s: 120.0, max_s: 180.0)
    end
  end

  it "pairs each block with the next answer on the same run" do
    expect(result.time_to_answer).to eq(count: 2, median_s: 450.0, max_s: 600.0)
  end

  it "counts each PR outcome once" do
    expect(result.pr_outcomes).to eq("opened" => 2, "reviewed" => 1, "merged" => 1, "closed" => 1)
  end

  it "groups usage by adapter and model, never across adapters, and keeps unpriced cost nil" do
    expect(result.usage_by_model.map { [it.adapter, it.model, it.cost_usd, it.estimated] })
      .to eq([["claude", "claude-opus-5-5", 3.5, true], ["codex", "gpt-5", nil, false]])
  end

  it "groups usage by run" do
    expect(result.usage_by_run.map { [it.run, it.adapter, it.invocations, it.input_tokens] })
      .to eq([["r1", "claude", 2, 300], ["r2", "codex", 1, 50]])
    expect(result.usage_by_run.first.incomplete).to be(true)
  end

  it "has no rates on an empty log, rather than dividing by zero" do
    empty = OpenLanes::Events.report([])

    expect(empty).to have_attributes(runs: 0,
      completion_rate: nil,
      intervention_rate: nil,
      time_to_answer: { count: 0, median_s: nil, max_s: nil })
    expect(empty.to_h.keys).to eq(OpenLanes::Events::Report::Result.members)
  end
end
