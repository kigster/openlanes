# frozen_string_literal: true

RSpec.describe OpenLanes::Events::Identity do
  let(:inputs) do
    { node: "n1", checkout: "c1", plan: "020.01", round: 1, agent: "backend-coder",
      invocation_start: Time.utc(2026, 10, 16, 12), kind: "agent_started", seq: 0 }
  end

  it "gives the same id for the same invocation" do
    first = described_class.event_id(**inputs)
    replayed = described_class.event_id(**inputs.dup)

    expect(replayed).to eq(first)
    expect(first).to match(/\A\h{64}\z/)
  end

  it "reads a Time and its ISO 8601 text as one start" do
    expect(described_class.event_id(**inputs, invocation_start: "2026-10-16T12:00:00.000Z"))
      .to eq(described_class.event_id(**inputs))
  end

  %i[node checkout plan round agent invocation_start kind seq].each do |key|
    it "changes when #{key} changes" do
      changed = inputs.merge(key => key == :invocation_start ? Time.utc(2026, 10, 16, 13) : "other")

      expect(described_class.event_id(**changed)).not_to eq(described_class.event_id(**inputs))
    end
  end
end
