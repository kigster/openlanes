# frozen_string_literal: true

RSpec.describe OpenLanes::Events::Event do
  let(:at) { Time.utc(2026, 10, 16, 12, 0, 0) }

  # One legal payload per kind, every allowed key filled.
  def payload_for(kind) = described_class::PAYLOAD_KEYS.fetch(kind).to_h { [it, it == "error_class" ? "Errno::ENOSPC" : 1] }

  def build(kind, **overrides)
    fields = { event_id: "e-#{kind}", kind:, at:, project: "demo", plan: "020.01", run: "r1", agent: "backend-coder",
               adapter: "claude", model: "claude-opus-5-5", payload: payload_for(kind) }
    described_class.new(**fields, **overrides)
  end

  described_class::KINDS.each do |kind|
    it "builds #{kind} with every field" do
      event = build(kind)

      expect(event).to have_attributes(event_id: "e-#{kind}",
        kind:,
        at: "2026-10-16T12:00:00.000Z",
        project: "demo",
        plan: "020.01",
        run: "r1",
        agent: "backend-coder",
        adapter: "claude",
        model: "claude-opus-5-5")
      expect(event.payload.keys).to match_array(described_class::PAYLOAD_KEYS.fetch(kind))
    end

    it "serialises #{kind} with no key outside the allowlist" do
      line = JSON.parse(build(kind).to_json)

      expect(line.keys).to match_array(described_class.members.map(&:to_s))
      expect(line["payload"].keys - described_class::PAYLOAD_KEYS.fetch(kind)).to be_empty
    end
  end

  it "has a payload allowlist for every kind and no other" do
    expect(described_class::PAYLOAD_KEYS.keys).to match_array(described_class::KINDS)
  end

  it "refuses a payload key the kind does not allow, so no text can slip in" do
    expect { build("block_raised", payload: { "question" => "Which database?" }) }
      .to raise_error(ArgumentError, /block_raised may not carry question/)
  end

  it "refuses an unknown kind" do
    expect { described_class.new(event_id: "x", kind: "chat", at:) }.to raise_error(ArgumentError, /unknown event kind/)
  end

  it "cuts error_class to its limit" do
    event = described_class.new(event_id: "x", kind: "failure", at:, payload: { error_class: "E" * 500 })

    expect(event.payload["error_class"].length).to eq(described_class::ERROR_CLASS_LIMIT)
  end

  it "round-trips through JSON" do
    event = build("agent_finished")

    expect(described_class.from_h(JSON.parse(event.to_json))).to eq(event)
  end

  it "refuses a line with no event_id" do
    expect { described_class.from_h("kind" => "run_started", "at" => "x") }.to raise_error(KeyError)
  end
end
