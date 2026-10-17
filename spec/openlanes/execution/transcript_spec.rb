# frozen_string_literal: true

require "spec_helper"

# A fifteen-minute agent used to sit behind a spinner showing only its name.
# This is what turns `claude --output-format stream-json` into the phrase that
# line has room for.
RSpec.describe OpenLanes::Execution::Transcript do
  subject(:transcript) { described_class.new { |progress| seen << progress.activity } }

  let(:seen) { [] }

  def assistant(*blocks) = { type: "assistant", message: { content: blocks } }.to_json + "\n"
  def tool(name, input) = { type: "tool_use", name: name, input: input }
  def text(body) = { type: "text", text: body }

  # One chunk per call, the way `readpartial` hands them over.
  def feed(*chunks) = chunks.each { |chunk| transcript.push(chunk) }

  def delta(usage, parent: nil)
    { type: "stream_event", parent_tool_use_id: parent, event: { type: "message_delta", usage: } }.to_json + "\n"
  end

  def started(id, tool_use_id: "toolu_1")
    { type: "system", subtype: "task_started", task_id: id, tool_use_id: }.to_json + "\n"
  end

  def spent(id, total, subtype: "task_notification")
    { type: "system", subtype:, task_id: id, usage: { total_tokens: total } }.to_json + "\n"
  end

  # The meter is the number on the spinner line and the number in the closing
  # report, and every one of these is a way `claude` reports spend that would
  # otherwise be counted twice or not at all.
  # The car's context meter: what the agent's own context holds now, which is
  # the latest message's whole input, not the sum of every turn's.
  describe "the context" do
    let(:usage) { { "input_tokens" => 2, "cache_creation_input_tokens" => 100, "cache_read_input_tokens" => 900, "output_tokens" => 40 } }

    it "is unknown until a message closes" do
      expect([transcript.context, transcript.progress.context]).to eq([nil, nil])
    end

    context "with two turns and a sub-agent's message" do
      before do
        feed(delta(usage), delta(usage.merge("cache_read_input_tokens" => 5000)), delta(usage, parent: "toolu_1"))
      end

      it "is the main agent's latest message's input, cache reads and writes included" do
        expect([transcript.context, transcript.progress.context]).to eq([5102, 5102])
      end
    end
  end

  describe "the meter" do
    it "counts everything that went up, cache reads included" do
      transcript.push(delta({ "input_tokens" => 2, "cache_creation_input_tokens" => 100,
                              "cache_read_input_tokens" => 900, "output_tokens" => 40 }))

      expect(transcript.up).to eq(1002)
    end

    it "keeps the cache reads apart, so a budget can leave them out" do
      transcript.push(delta({ "input_tokens" => 2, "cache_creation_input_tokens" => 100,
                              "cache_read_input_tokens" => 900, "output_tokens" => 40 }))

      expect(transcript).to have_attributes(cached: 900, fresh: 142)
    end

    # The `assistant` event carries a usage block whose output count is the
    # placeholder the API sends when a message starts: 2, for an answer of
    # four thousand tokens. Only `message_delta` settles it.
    it "counts what a message settles at, not what it started at" do
      transcript.push(assistant(text("Working.")))
      transcript.push(delta({ "input_tokens" => 1, "output_tokens" => 3163 }))

      expect(transcript.down).to eq(3163)
    end

    it "adds what a sub-agent spent, since claude leaves it out of the parent's own total" do
      feed(started("t1"), spent("t1", 34_116))

      aggregate_failures do
        expect(transcript.up).to eq(34_116)
        expect(transcript.spawned).to eq(1)
        expect(transcript.delegated).to eq(34_116)
      end
    end

    # A sub-agent reports its total cumulatively, several times over. Adding
    # those up would report a 34k sub-agent as having spent a quarter of a
    # million.
    it "takes a sub-agent's last report rather than the sum of them" do
      feed(started("t1"),
        spent("t1", 12_000, subtype: "task_progress"),
        spent("t1", 30_000, subtype: "task_progress"),
        spent("t1", 34_116))

      expect(transcript.up).to eq(34_116)
    end

    # Some sub-agents stream their own messages past the parent, carrying the
    # tool call they belong to. Those are already counted.
    it "does not count a sub-agent twice when its own messages stream past" do
      feed(started("t1", tool_use_id: "toolu_9"),
        delta({ "input_tokens" => 1000, "output_tokens" => 50 }, parent: "toolu_9"),
        spent("t1", 34_116))

      aggregate_failures do
        expect(transcript.up).to eq(1000)
        expect(transcript.down).to eq(50)
        expect(transcript.delegated).to be_zero
      end
    end

    # The `result` event is the invocation's own final accounting, so it
    # replaces what the stream accumulated rather than adding to it.
    it "lets the result event settle the total it kept a running count of" do
      feed(delta({ "input_tokens" => 5, "output_tokens" => 5 }))
      transcript.push({ type: "result", usage: { "input_tokens"                => 8,
                                                 "cache_creation_input_tokens" => 61_673,
                                                 "cache_read_input_tokens"     => 239_937,
                                                 "output_tokens"               => 3163 } }.to_json + "\n")

      aggregate_failures do
        expect(transcript.up).to eq(301_618)
        expect(transcript.down).to eq(3163)
      end
    end

    it "reports both directions and the sub-agent count in one snapshot" do
      feed(started("t1"),
        spent("t1", 1000),
        delta({ "input_tokens" => 10, "output_tokens" => 20 }))

      expect(transcript.progress).to have_attributes(up: 1010, down: 20, subagents: 1)
    end
  end

  describe "#push" do
    it "reports a tool call as something being done, not as a tool name" do
      transcript.push(assistant(tool("Edit", { "file_path" => "/a/b/spec.md" })))

      expect(seen).to eq(["editing spec.md"])
    end

    it "narrates from what the agent says when it is not calling a tool" do
      transcript.push(assistant(text("Writing the Goals section now. Then the rest.")))

      expect(seen).to eq(["Writing the Goals section now."])
    end

    # An agent that says "now I'll edit the spec" and then edits it is more
    # usefully reported as editing it.
    it "prefers the most recent block in a message" do
      transcript.push(assistant(text("Next I will read the plan."), tool("Read", { "file_path" => "plan.md" })))

      expect(seen).to eq(["reading plan.md"])
    end

    # readpartial splits wherever it likes, so a line arriving in two chunks is
    # the normal case rather than the edge one.
    it "reassembles a line split across chunks" do
      whole = assistant(tool("Write", { "file_path" => "blocked.md" }))
      transcript.push(whole[0, 30])
      transcript.push(whole[30..])

      expect(seen).to eq(["writing blocked.md"])
    end

    it "says nothing twice in a row about the same thing" do
      2.times { transcript.push(assistant(tool("Read", { "file_path" => "spec.md" }))) }

      expect(seen).to eq(["reading spec.md"])
    end

    it "caps a runaway phrase" do
      transcript.push(assistant(text("x" * 1000)))

      expect(seen.first.length).to be <= described_class::LIMIT
    end
  end

  describe "what the agent says to the harness" do
    it "keeps the last SendUserMessage as the progress message" do
      seen = []
      transcript = described_class.new { |p| seen << p.message }
      transcript.push(%({"type":"assistant","message":{"content":[{"type":"tool_use","name":"SendUserMessage","input":{"message":"halfway through the schema"}}]}}\n))
      expect(seen.last).to eq("halfway through the schema")
    end
  end

  # `claude` reports the failures that matter most as prose, never as an event:
  # the 401 that cost a whole round three minutes an agent printed on stdout
  # and emitted nothing at all.
  describe "output that is not JSON" do
    it "keeps it rather than discarding it" do
      transcript.push("Failed to authenticate. API Error: 401 API key is invalid.\n")

      aggregate_failures do
        expect(transcript.plain).to include("Failed to authenticate. API Error: 401 API key is invalid.")
        expect(seen).to be_empty
      end
    end

    it "survives a line that starts like JSON and is not" do
      expect { transcript.push("{not json at all\n") }.not_to raise_error
    end
  end

  describe "the result event" do
    it "records what the agent finally said" do
      transcript.push({ type: "result", subtype: "success", result: "done", is_error: false }.to_json + "\n")

      aggregate_failures do
        expect(transcript.result).to eq("done")
        expect(transcript).not_to be_failed
      end
    end

    it "treats an error result as a failure with the agent's own words" do
      transcript.push({ type: "result", result: "hit the turn limit", is_error: true }.to_json + "\n")

      aggregate_failures do
        expect(transcript).to be_failed
        expect(transcript.error).to eq("hit the turn limit")
      end
    end
  end

  # `--include-partial-messages` is what makes the meter possible and also
  # emits one event per handful of generated characters. The trace is read by
  # a person looking for why a run failed, and those bury everything else.
  describe "what the trace keeps" do
    it "keeps the events a failed run is read for, and drops the delta noise" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "trace.ndjson")
        described_class.new(trace: path) do |_|
        end.tap { |t|
          t.push({ type: "stream_event", event: { type:  "content_block_delta",
                                                  delta: { type: "text_delta", text: "Fol" } } }.to_json + "\n")
          t.push({ type: "result", result: "Folded B3." }.to_json + "\n")
          t.finish
        }

        aggregate_failures do
          expect(File.read(path)).to include("Folded B3.")
          expect(File.read(path)).not_to include("content_block_delta")
        end
      end
    end
  end

  # The tile's extra lines: how many sub-agents are in flight now, which has
  # to fall again when they end, unlike the cumulative count beside it.
  describe "sub-agents in flight" do
    def ended(id, status) = { type: "system", subtype: "task_notification", task_id: id, status: }.to_json + "\n"
    def result = { type: "result", result: "done", is_error: false }.to_json + "\n"

    it "counts started tasks until each one's notification arrives" do
      feed(started("a"), started("b"), ended("a", "completed"))
      after_first = transcript.running
      feed(ended("b", "completed"))

      expect([after_first, transcript.running, transcript.spawned]).to eq([1, 0, 2])
    end

    it "ends a task that failed or was stopped" do
      feed(started("a"), started("b"), ended("a", "failed"), ended("b", "stopped"))

      expect(transcript.running).to eq(0)
    end

    it "keeps a task in flight on a status it does not know" do
      feed(started("a"), ended("a", "pending"))

      expect(transcript.running).to eq(1)
    end

    it "does not reopen a task whose notification overtook its start" do
      feed(ended("a", "completed"), started("a"))

      expect(transcript.running).to eq(0)
    end

    it "is 0 once the result arrives, while the cumulative count stays" do
      feed(started("a"), started("b"), result)

      expect([transcript.running, transcript.spawned, transcript.progress.subagents]).to eq([0, 2, 2])
    end

    it "is 0 once the stream ends without a result" do
      feed(started("a"))
      transcript.finish

      expect(transcript.progress.running).to eq(0)
    end

    it "is published on every progress" do
      counts = []
      watched = described_class.new { counts << it.running }
      [started("a"), ended("a", "completed")].each { watched.push(it) }

      expect(counts).to eq([1, 0])
    end

    # Recorded from `claude -p --output-format stream-json --verbose` with a
    # prompt that fanned out to two sub-agents, ids and paths made fictional.
    it "replays a real fan-out to 0 in flight and 2 spawned" do
      counts = []
      replay = described_class.new { counts << it.running }
      replay.push(File.read(File.expand_path("../../fixtures/streams/subagent-fanout.ndjson", __dir__)))
      replay.finish

      aggregate_failures do
        expect(counts.max).to eq(2)
        expect([replay.running, replay.spawned]).to eq([0, 2])
      end
    end
  end

  describe "#finish" do
    it "consumes a last line that never got its newline" do
      transcript.push(assistant(tool("Bash", { "command" => "bundle exec rspec" })).chomp)
      transcript.finish

      expect(seen).to eq(["running bundle exec rspec"])
    end
  end

  # What a compaction resumes, and how it knows `/compact` did anything (W28).
  describe "the session" do
    def system_event(subtype, **rest) = { type: "system", subtype:, session_id: "sess-1", **rest }.to_json + "\n"

    it "is unknown until the stream starts" do
      expect([transcript.session, transcript.progress.session]).to eq([nil, nil])
    end

    context "when the init event has gone past" do
      subject(:transcript) { described_class.new { |progress| sessions << progress.session } }

      let(:sessions) { [] }

      before { feed(system_event("init"), system_event("init", session_id: "sess-2")) }

      it "is the first one named, handed on with the progress" do
        expect([transcript.session, sessions.last]).to eq(%w[sess-1 sess-1])
      end
    end

    it "has not been compacted until a compact_boundary says so" do
      expect(transcript.compacted).to be_nil
    end

    it "keeps what the compact_boundary reported" do
      feed(system_event("compact_boundary", compact_metadata: { pre_tokens: 46_599, post_tokens: 7240 }))
      expect(transcript.compacted).to include("pre_tokens" => 46_599, "post_tokens" => 7240)
    end
  end
end
