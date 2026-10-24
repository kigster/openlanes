# frozen_string_literal: true

RSpec.describe OpenLanes::Events::Usage do
  let(:claude_totals) do
    { input_tokens: 1_000_000, output_tokens: 100_000, cache_read_input_tokens: 50, cache_creation_input_tokens: 7 }
  end

  it "prices claude from its model table and marks the cost estimated" do
    usage = described_class.from(adapter: "claude", model: "claude-opus-5-5", totals: claude_totals)

    expect(usage).to have_attributes(adapter: "claude",
      input_tokens: 1_000_000,
      output_tokens: 100_000,
      cache_read_tokens: 50,
      cache_write_tokens: 7,
      cost_usd: 6.0,
      estimated: true,
      incomplete: false)
  end

  it "flags a claude run that spawned sub-agents as incomplete" do
    usage = described_class.from(adapter: "claude", model: "claude-opus-5-5", totals: claude_totals, subagents_spawned: 2)

    expect(usage.incomplete).to be(true)
  end

  it "never reads total_cost_usd" do
    usage = described_class.from(adapter: "claude",
      model: "claude-opus-5-5",
      totals: claude_totals.merge(total_cost_usd: 999.0))

    expect(usage.cost_usd).to eq(6.0)
  end

  it "leaves codex cost nil, not 0, and reads its cached tokens" do
    usage = described_class.from(adapter: "codex",
      model: "gpt-5",
      totals: { "input_tokens" => 10, "cached_input_tokens" => 4, "output_tokens" => 3 })

    expect(usage).to have_attributes(input_tokens: 10,
      output_tokens: 3,
      cache_read_tokens: 4,
      cost_usd: nil,
      estimated: false,
      incomplete: false)
  end

  it "leaves pi cost nil, not 0, and its missing fields nil" do
    usage = described_class.from(adapter: "pi", model: nil, totals: { up: 5 })

    expect(usage).to have_attributes(input_tokens: 5, output_tokens: nil, cache_read_tokens: nil, cost_usd: nil)
  end

  it "has no cost for an unknown claude model rather than a guess" do
    usage = described_class.from(adapter: "claude", model: "not-a-model", totals: claude_totals)

    expect(usage).to have_attributes(cost_usd: nil, estimated: false)
  end

  it "takes an injected price" do
    model = OpenLanes::Adapters::Model.new(id: "m", label: "M", rate_in: 1, rate_out: 1)
    usage = described_class.from(adapter: "claude", model: "m", totals: { up: 1_000_000, down: 0 }, price: ->(_) { model })

    expect(usage.cost_usd).to eq(1.0)
  end

  it "serialises to the agent_finished usage keys" do
    usage = described_class.from(adapter: "codex", model: nil, totals: {})

    expect(usage.to_h.keys).to match_array(OpenLanes::Events::Event::USAGE_KEYS)
  end
end
