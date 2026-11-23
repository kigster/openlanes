# frozen_string_literal: true

require "yaml"

# Plan 045.03: the executor is cut into collaborators with no behaviour
# change, and this is the proof. A real Executor, built through
# Execution.executor, runs in a real plans tree with the real Boundary,
# Control, Clock, Prompt and Transcript; only the agent CLI is scripted.
# For each scenario it records the argv handed to the spawner (temporary
# paths replaced by placeholders), every Result field but the wall clock
# and the pid, the restart record's keys, the trace's line count and the
# activity passed to the progress block, and compares them with the same
# scenarios recorded before the cut.
#
# To record the fixture again, run this file on the commit to compare
# against with OPENLANES_CAPTURE_FIXTURE=1; it then writes the fixture
# instead of reading it.
RSpec.describe "the executor after its split, against the runs recorded before it", :tree do
  let(:fixture) { File.expand_path("../../fixtures/executor_split/runs.yml", __dir__) }
  let(:root) { File.dirname(plans_root) }
  let(:traces) { Dir.mktmpdir("executor-split-traces") }
  let(:agent) { OpenLanes::Agents.find("backend-coder") }
  let(:confined) { agent.with(confined_to: ["spec.md"], adapter: "codex") }
  let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:broken) { instance_double(Process::Status, success?: false, exitstatus: 1) }
  let(:spawned) { [] }
  let(:playing) { [] }
  let(:spawn) do
    lambda do |argv, **|
      spawned << argv
      chunks, status = playing.fetch(spawned.size - 1)
      child(chunks, status)
    end
  end
  let(:throttle) do
    OpenLanes::Execution::Throttle::Backoff.new(random: instance_double(Random, rand: 0.0), sleep: ->(_) {})
  end
  let(:plan) do
    plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end

  after do
    OpenLanes::Execution::Control.reset!
    FileUtils.rm_rf(traces)
  end

  def event(hash) = "#{JSON.generate(hash)}\n"

  def init = event(type: "system", subtype: "init", session_id: "sess-1")

  def delta(sent, made) = event(type: "stream_event", event: { type: "message_delta", usage: { input_tokens: sent, output_tokens: made } })

  def said(text) = event(type: "assistant", message: { content: [{ type: "text", text: }] })

  def finished(sent, made)
    event(type: "result",
      subtype: "success",
      is_error: false,
      result: "done",
      session_id: "sess-1",
      usage: { input_tokens: sent, output_tokens: made })
  end

  def limited
    event(type: "result",
      subtype: "error_during_execution",
      is_error: true,
      session_id: "sess-1",
      result: "API Error: 429 rate_limit_error. retry-after: 20",
      usage: { input_tokens: 0, output_tokens: 0 })
  end

  def child(chunks, status)
    child = instance_double(OpenLanes::Execution::Child, pid: 100 + spawned.size, alive?: false, kill: nil, terminate: nil, wait: status)
    allow(child).to receive(:each_chunk) { |&block| chunks.each { block.call(it) } }
    child
  end

  def executor(**) = OpenLanes::Execution.executor(root:, spawn:, trace_dir: traces, throttle:, memory: false, **)

  # Temporary directories, the trace's timestamped name and the control
  # file's suffix differ on every run; what the argv says around them does not.
  def scrub(text)
    text.to_s
        .gsub(traces, "<traces>")
        .gsub(File.realpath(root), "<root>").gsub(root, "<root>")
        .gsub(/control-[^\s"']+/, "control-<id>")
        .gsub(/\d{8}-\d{6}-[^\s"']+\.ndjson/, "<trace>.ndjson")
        .gsub(/\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?[^\s"']*/, "<time>")
  end

  # `offered` and `cited` (decision C5) came after the split and are covered
  # by executor_memory_spec; left out so the recorded fixture stays the record.
  def result_fields(result) = result.to_h.except(:seconds, :pid, :offered, :cited).transform_keys(&:to_s).transform_values { scrub_value(it) }

  def scrub_value(value) = value.is_a?(String) ? scrub(value) : value

  # One scenario on a fresh executor and a fresh spawn log, so one cannot
  # leak into the next. The agent may be swapped for one confined to a
  # file, on a CLI that cannot confine it.
  def run(streams, handle: OpenLanes::Execution::Executor::Handle.new, agent: self.agent, **)
    playing.replace(streams)
    spawned.clear
    restarts = []
    handle.on_restart = ->(fields) { restarts << fields.keys.map(&:to_s).sort }
    shown = []
    result = executor(**).call(agent, plan, handle:) { |progress| shown << scrub(progress.activity) }
    summary(result, handle).merge("restart" => restarts, "progress" => shown)
  end

  def summary(result, handle)
    { "argv" => spawned.map { shape(it) }, "prompts" => spawned.map { headings(it) },
      "result" => result_fields(result), "trace_lines" => trace_lines(handle) }
  end

  # The prompt follows -p. Its text belongs to the agent's definition, which
  # this plan does not change and other plans do; which sections it was
  # assembled from is the executor's doing, so that is what is compared.
  def prompt_at(argv) = argv.index("-p")&.then { argv[it + 1] }

  def shape(argv) = argv.map { it.equal?(prompt_at(argv)) ? "<prompt>" : scrub(it) }

  def headings(argv) = prompt_at(argv).to_s.split("\n## This invocation").last.lines.grep(/\A## /).map { scrub(it.chomp) }

  def trace_lines(handle) = handle.trace && File.exist?(handle.trace) ? File.readlines(handle.trace).size : nil

  # Codex is marked usable by hand, so the probe cannot swap it for a CLI
  # that would confine the agent; nothing is started.
  def unconfinable = [[], { agent: confined, usable: ->(_) { true } }]

  # Each scenario: the processes the spawner plays back, in turn, and the
  # options its executor is built with.
  def scenarios
    {
      "unconfinable" => unconfinable,
      "success"      => [[[[init, delta(100, 10), said("Built it."), finished(100, 10)], ok]], {}],
      "dry_run"      => [[], { dry_run: true }],
      "throttled"    => [[[[init, limited], broken], [[init, delta(50, 5), finished(50, 5)], ok]], {}],
      "exit_failed"  => [[[[init, said("Something broke.")], broken]], {}],
      "budget_kill"  => [[[[init, delta(900, 200), finished(900, 200)], ok]], { max_tokens: 500 }]
    }
  end

  def recorded = scenarios.transform_values { |(streams, options)| run(streams, **options) }

  it "runs every scenario as it ran before the split" do
    runs = recorded
    if ENV["OPENLANES_CAPTURE_FIXTURE"]
      FileUtils.mkdir_p(File.dirname(fixture))
      File.write(fixture, YAML.dump(runs))
    end
    expect(runs).to eq(YAML.safe_load_file(fixture, permitted_classes: [Symbol]))
  end
end
