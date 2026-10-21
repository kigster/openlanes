# frozen_string_literal: true

require "json_schemer"

# B5: a real round, with an executor that sets the handle the way the real
# one does (a child with a pid, a session id, a trace that grows), leaves a
# schema-valid progress journal under the runtime directory, never in .plans.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:root) { File.dirname(plans_root) }
  let(:agents_dir) { Dir.mktmpdir }
  let(:trace) { File.join(Dir.mktmpdir, "trace.ndjson") }
  let(:agents) do
    File.write(File.join(agents_dir, "leah.md"),
      "---\nname: leah-researcher\nhandles: [new]\nadvances_to: researched\nrounds: 1\n" \
      "adapter: claude\nledger: [spec.md]\n---\nbody")
    OpenLanes::Agents::Registry.new(dir: agents_dir)
  end
  let(:event_journal) { OpenLanes::Engine::EventJournal.new(root:, run_id: "spec", node: "n") }
  let(:executor) do
    trace_file = trace
    lambda { |_agent, _subject, handle:, **, &progress|
      handle.child = Struct.new(:pid).new(Process.pid)
      handle.trace = trace_file
      File.write(trace_file, "{}\n")
      progress.call(OpenLanes::Execution::Transcript::Progress.new(activity: nil, up: 0, down: 0, subagents: 0))
      sleep 0.05
      handle.session = "s-1"
      File.write(trace_file, "{}\n{}\n")
      sleep 0.05
      OpenLanes::Execution::Executor::Result.new(ok: false, note: "killed", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
    }
  end
  let(:schema) { JSONSchemer.schema(Pathname.new(OpenLanes::Engine::EventJournal::SCHEMA_PATH)) }
  let(:events) { File.readlines(event_journal.path).map { JSON.parse(it) } }

  before do
    plans { |t| t.plan "001.00", :new, "remember", files: { "spec.md" => spec_body } }
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :shared,
      jobs: 1,
      sleeper: ->(_) { sleep 0.02 },
      journal: event_journal,
      extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false)).call
    event_journal.close
  end

  after { FileUtils.rm_rf(agents_dir) }

  it "writes the run's events in order, each one schema-valid" do
    kinds = events.map { it["kind"] }
    expect(kinds.first(3)).to eq(%w[run_started plan_assigned agent_started])
    expect(kinds).to include("agent_offset", "agent_ended")
    expect(kinds.last).to eq("run_ended")
    expect(events.flat_map { schema.validate(it).map { |e| e["error"] } }).to eq([])
  end

  it "names the agent's pid, trace, session and last offset" do
    started = events.find { it["kind"] == "agent_started" }
    expect(started).to include("plan" => "001.00", "agent" => "leah-researcher", "pid" => Process.pid, "output_file" => trace)
    expect(events.select { it["kind"] == "agent_offset" }.map { it["offset"] }.last).to eq(File.size(trace))
  end

  it "records the session id once the stream names it" do
    named = events.select { %w[agent_started agent_session].include?(it["kind"]) }.filter_map { it["session_id"] }
    expect(named).to eq(["s-1"])
  end

  it "keeps the journal out of .plans" do
    expect(Dir.glob(File.join(plans_root, "**", "*.ndjson"))).to be_empty
  end
end
