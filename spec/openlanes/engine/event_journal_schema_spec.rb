# frozen_string_literal: true

require "json_schemer"

JOURNAL_SAMPLES = {
  "run_started"   => { "jobs" => 2, "isolation" => "worktree" },
  "run_ended"     => { "reason" => "fixed point" },
  "plan_assigned" => { "plan" => "039.00", "agent" => "backend-coder", "round" => 1 },
  "agent_started" => { "plan" => "039.00", "agent" => "backend-coder", "round" => 1, "pid" => 4242,
                       "started_at" => nil, "session_id" => nil, "output_file" => "/tmp/t.ndjson" },
  "agent_session" => { "plan" => "039.00", "agent" => "backend-coder", "session_id" => "s-1" },
  "agent_offset"  => { "plan" => "039.00", "agent" => "backend-coder", "offset" => 1024 },
  "agent_ended"   => { "plan" => "039.00", "agent" => "backend-coder", "exit" => 0 },
  "transition"    => { "plan" => "039.00", "from" => "building", "to" => "review", "event" => "review" },
  "extension"     => { "plan" => "039.00", "agent" => "backend-coder", "seconds" => 600 },
  "question"      => { "plan" => "039.00", "agent" => "backend-coder", "note" => "technical" }
}.freeze

# B1: every kind the journal writes, against schemas/journal-event.schema.json.
RSpec.describe "schemas/journal-event.schema.json" do
  let(:schema) { JSONSchemer.schema(Pathname.new(OpenLanes::Engine::EventJournal::SCHEMA_PATH)) }
  let(:base) { { "v" => 1, "seq" => 1, "at" => "2026-10-21T10:00:00.000000Z", "node" => "mbp:abc123", "run_id" => "r1" } }
  let(:agent) { { "plan" => "039.00", "agent" => "backend-coder" } }

  it "has a sample for every kind the writer knows" do
    expect(JOURNAL_SAMPLES.keys).to match_array(OpenLanes::Engine::EventJournal::KINDS)
  end

  JOURNAL_SAMPLES.each do |kind, fields|
    it "accepts #{kind}" do
      expect(schema.validate(base.merge("kind" => kind).merge(fields)).map { it["error"] }).to eq([])
    end
  end

  it "rejects a line without v" do
    expect(schema).not_to be_valid(base.except("v").merge("kind" => "run_ended"))
  end

  it "rejects an unknown kind" do
    expect(schema).not_to be_valid(base.merge("kind" => "teleported"))
  end

  it "rejects agent_started without pid" do
    expect(schema).not_to be_valid(base.merge("kind" => "agent_started").merge(JOURNAL_SAMPLES["agent_started"].except("pid")))
  end

  it "rejects a negative offset" do
    expect(schema).not_to be_valid(base.merge("kind" => "agent_offset").merge(agent, "offset" => -1))
  end
end
