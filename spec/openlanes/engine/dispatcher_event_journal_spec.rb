# frozen_string_literal: true

require "json_schemer"

# B5: a real round, with an executor that sets the handle the way the real
# one does (a child with a pid, a session id, a trace that grows), leaves a
# schema-valid progress journal under the runtime directory, never in .plans.
# One plan advances (transition), one blocks (question), and a console asks
# for more time while an agent runs (extension), so every kind a dispatcher
# writes is written here.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:root) { File.dirname(plans_root) }
  let(:stamp) { "2026-10-21 10:00:00 AM PDT" }
  let(:agents_dir) { Dir.mktmpdir }
  let(:trace) { File.join(Dir.mktmpdir, "trace.ndjson") }
  let(:agents) do
    File.write(File.join(agents_dir, "researcher.md"),
      "---\nname: researcher\nhandles: [new]\nadvances_to: researched\nrounds: 1\n" \
      "adapter: claude\nledger: [spec.md]\n---\nbody")
    OpenLanes::Agents::Registry.new(dir: agents_dir)
  end
  let(:event_journal) { OpenLanes::Engine::EventJournal.new(root:, run_id: "spec", node: "n") }
  let(:executor) do
    trace_file = trace
    body = spec_body
    signed = stamp
    lambda { |agent, subject, handle:, round: 1, **, &progress|
      handle.child = Struct.new(:pid).new(Process.pid)
      handle.trace = trace_file
      File.write(trace_file, "{}\n")
      progress.call(OpenLanes::Execution::Transcript::Progress.new(activity: nil, up: 0, down: 0, subagents: 0))
      sleep 0.05
      handle.session = "s-#{subject.feature.ordinal}"
      File.write(trace_file, "{}\n{}\n")
      sleep 0.05
      dir = subject.feature.path
      status = if subject.feature.ordinal.to_s == "001.00"
                 File.write(File.join(dir, "spec.md"), "#{body}\n## Research\n\nFound.\n")
                 "Completed, round #{round}"
               else
                 File.write(File.join(dir, "blocked.md"),
                   "# Blocked\n\n## B1 Which store\n\nContext.\n\na) Redis (Recommended)\nb) Postgres\n")
                 "Blocked, round #{round} (technical)"
               end
      OpenLanes::Plans::Ledger.append(File.join(dir, "spec.md"),
        "> [#{signed}] [ agent: #{agent.name}   status: #{status} ]")
      OpenLanes::Execution::Executor::Result.new(ok: true, note: "done", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
    }
  end
  let(:schema) { JSONSchemer.schema(Pathname.new(OpenLanes::Engine::EventJournal::SCHEMA_PATH)) }
  let(:events) { File.readlines(event_journal.path).map { JSON.parse(it) } }

  before do
    plans do |t|
      t.plan "001.00", :new, "remember", files: { "spec.md" => spec_body }
      t.plan "002.00", :new, "wonder", files: { "spec.md" => spec_body }
    end
    extended = []
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :shared,
      jobs: 1,
      sleeper: ->(_) { sleep 0.02 },
      journal: event_journal,
      extensions: OpenLanes::Engine::Extensions.new(stay: false, auto: false)).call do |dispatcher|
      dispatcher.before_tick do |d|
        d.running.reject { extended.include?(it.key) || it.handle.nil? }.each do |job|
          extended << job.key
          d.extend(job.key, 60)
        end
      end
    end
    event_journal.close
  end

  after { FileUtils.rm_rf(agents_dir) }

  it "writes the run's events in order, each one schema-valid" do
    kinds = events.map { it["kind"] }.grep_v("extension") # a console may ask at any tick
    expect(kinds.first(3)).to eq(%w[run_started plan_assigned agent_started])
    expect(kinds).to include("agent_offset", "agent_ended")
    expect(kinds.last).to eq("run_ended")
    expect(events.flat_map { schema.validate(it).map { |e| e["error"] } }).to eq([])
  end

  it "writes every kind a dispatcher emits" do
    expect(events.map { it["kind"] }.uniq).to match_array(OpenLanes::Engine::EventJournal::KINDS)
  end

  it "names the aasm event a transition fired, not its destination" do
    expect(events.select { it["kind"] == "transition" })
      .to include(include("plan" => "001.00", "from" => "new", "to" => "researched", "event" => "research"))
  end

  it "records a blocked agent's question and a console's extension" do
    expect(events.find { it["kind"] == "question" }).to include("plan" => "002.00", "agent" => "researcher", "note" => "blocked")
    expect(events.select { it["kind"] == "extension" }.map { it["seconds"] }).to all(eq(60))
  end

  it "names the agent's pid, trace, session and last offset" do
    started = events.find { it["kind"] == "agent_started" }
    expect(started).to include("plan" => "001.00", "agent" => "researcher", "pid" => Process.pid, "output_file" => trace)
    expect(events.select { it["kind"] == "agent_offset" }.map { it["offset"] }.last).to eq(File.size(trace))
  end

  it "records the session id once the stream names it" do
    named = events.select { %w[agent_started agent_session].include?(it["kind"]) }.filter_map { it["session_id"] }
    expect(named).to eq(%w[s-001.00 s-002.00])
  end

  it "says the run ended at a fixed point" do
    expect(events.last).to include("kind" => "run_ended", "reason" => "fixed point")
  end

  it "keeps the journal and every runtime file out of .plans" do
    expect(Dir.glob(File.join(plans_root, "**", "{*.ndjson,*.lock,*.tmp,openlanes-state.json}"))).to be_empty
  end
end
