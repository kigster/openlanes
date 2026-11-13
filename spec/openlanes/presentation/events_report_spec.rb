# frozen_string_literal: true

RSpec.describe OpenLanes::Presentation::EventsReport do
  def usage(**over)
    OpenLanes::Events::Report::Usage.new(run: nil,
      adapter: "claude",
      model: "opus",
      invocations: 2,
      input_tokens: 100,
      output_tokens: 50,
      cost_usd: 1.234,
      estimated: true,
      incomplete: false,
**over)
  end

  def result(by_model:, **over)
    OpenLanes::Events::Report::Result.new(runs: 2,
      completion_rate: 0.5,
      blocks: 3,
      runs_needing_feedback: 2,
      intervention_rate: 1.0,
      time_to_answer: { count: 1, median_s: 60.0, max_s: 60.0 },
      pr_outcomes: { "opened" => 1, "reviewed" => 0, "merged" => 1, "closed" => 0 },
      usage_by_run: [],
      usage_by_model: by_model,
      skipped_lines: 0,
      memory: { on:  { runs: 2, approved: 1, rounds_mean: 1.5, rounds_median: 1.5 },
                off: { runs: 0, approved: 0, rounds_mean: nil, rounds_median: nil } },
**over)
  end

  it "compares reviews to approval with memory on and off" do
    text = described_class.new(result(by_model: [])).render

    expect(text).to include("Memory: reviews to approval",
      "  on   2 run(s), 1 approved, rounds mean 1.5, median 1.5",
      "  off  0 run(s), 0 approved, rounds mean n/a, median n/a")
  end

  it "labels a computed cost as an estimate" do
    text = described_class.new(result(by_model: [usage])).render
    expect(text).to include("$1.23 (est.)", "completion rate         50.0%", "3 over 2 unique run(s)")
  end

  it "renders an unpriced cost as unknown, never $0" do
    text = described_class.new(result(by_model: [usage(adapter: "codex", cost_usd: nil, estimated: false)])).render
    expect(text).to include("unknown")
    expect(text).not_to include("$0")
  end

  it "flags incomplete usage, and says so when nothing was recorded" do
    expect(described_class.new(result(by_model: [usage(incomplete: true)])).render).to include("incomplete")
    expect(described_class.new(result(by_model: [], skipped_lines: 2)).render).to include("none", "2 unreadable")
  end

  it "prints n/a for rates with no runs and for unanswered blocks" do
    text = described_class.new(result(by_model: [], completion_rate: nil, time_to_answer: { count: 0 })).render
    expect(text).to include("n/a", "no answered blocks")
  end

  it "renders JSON that parses back" do
    json = JSON.parse(described_class.new(result(by_model: [usage])).render(format: :json))
    expect(json["usage_by_model"].first["cost_usd"]).to eq(1.234)
  end
end
