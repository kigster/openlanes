# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

# Plan 020.01, F1: the durable run log, end to end. The real Runner, Unblocker
# and PrOutcomes write it; `exe/openlanes events report` reads it back in its
# own process. Only the executor and the GitHub seam are doubles.
RSpec.describe "Events report", :tree do
  let(:exe) { File.expand_path("../../exe/openlanes", __dir__) }
  let(:project_root) { File.dirname(plans_root) }
  let(:state_home) { Dir.mktmpdir("xdg-state") }
  let(:env) { { "XDG_STATE_HOME" => state_home } }
  let(:config) { OpenLanes::Config.new(project: "demo", events_enabled: true) }
  let(:sink) { OpenLanes::Events.emitter(root: project_root, config:, env:) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agents) { OpenLanes::Agents::Registry.new }
  let(:log_path) { File.join(OpenLanes::Events.dir(root: project_root, config:, env:), "#{sink.node}.jsonl") }

  # Plan 001.00 completes the phase it is asked for; it is asked; 002.00 stops on two questions.
  let(:executor) do
    lambda do |agent, subject, **|
      folder = subject.feature.path
      state = OpenLanes::Plans::PlanState.for(folder)
      if subject.feature.ordinal.to_s == "002.00"
        File.write(File.join(folder, "blocked.md"), "# Blocked\n\n## B1. Which vendor\n")
        state.sign!(agent: agent.name, round: 1, status: "Blocked", note: "product")
      else
        File.open(File.join(folder, "spec.md"), "a") { it.puts "\n## Research\n\n### Findings, Conclusion & References\n" }
        state.sign!(agent: agent.name, round: 1, status: "Completed")
      end
      OpenLanes::Execution::Executor::Result.new(ok: true,
        note: "done",
        up: 1_000,
        down: 100,
        subagents: 0,
        delegated: 0,
        seconds: 1.0)
    end
  end

  def openlanes(*args)
    out, err, status = Open3.capture3(env.merge("NO_COLOR" => "1"), exe, *args, chdir: project_root)
    raise "openlanes #{args.join(" ")} failed: #{err}" unless status.success?

    out
  end

  before do
    File.write(File.join(project_root, ".openlanes.yml"), "project: demo\nevents:\n  enabled: true\n")
    plans do |t|
      t.plan "001.00", :new, "completes", files: { "spec.md" => spec_body }
      t.plan "002.00", :new, "blocks", files: { "spec.md" => spec_body }
    end
    OpenLanes::Engine::Runner.new(tree:, executor:, agents:, sleeper: ->(_) {}, events: sink).call
  end

  after { FileUtils.rm_rf(state_home) }

  def answer_and_drain
    blocked = tree.reload.find("002.00")
    File.write(File.join(blocked.feature.path, "blocked.md"),
      "# Blocked\n\n## B1. Which vendor\n\n## A1. Acme\n\nDecided by Ada Example <ada@example.test>, 2026-10-01.\n")
    drain = lambda do |_agent, subject, **|
      File.delete(File.join(subject.feature.path, "blocked.md"))
      [true, "completed"]
    end
    unblocker = OpenLanes::Lifecycle::Unblocker.new(tree: tree.reload,
      agent: agents.find("unblocker"),
      executor: drain,
      commit: true,
      events: sink)
    unblocker.drain(tree.find("002.00"))
  end

  # The agent_finished lines, counted straight off the file rather than by
  # the report, so the two paths must agree.
  def finished = File.readlines(log_path).map { JSON.parse(it) }.select { it["kind"] == "agent_finished" }
  def completed = finished.count { it.dig("payload", "status") == "Completed" }

  def merge_a_pull_request
    plans { |t| t.plan "003.00", :in_review, "merged", files: { "spec.md" => spec_body }, prs: [t.open(13, "c")] }
    github = instance_double(OpenLanes::Vcs::GitHub, pulls: [{ number: 13, open: false, state: "Merged 🟣", labels: [] }])
    watch = OpenLanes::Engine::PrWatch.new(github:)
    effects = OpenLanes::Engine::PrOutcomes.new(tree_dir: plans_root, agents:, events: sink)
    watch.poll(OpenLanes::Plans::Tree.new(dir: plans_root).subjects).each { effects.apply(it) }
  end

  it "reports completion, a block, its answer, a merge and usage, and stores nothing off the allowlist" do
    answer_and_drain
    merge_a_pull_request
    report = JSON.parse(openlanes("events", "report", "--format", "json"))

    aggregate_failures do
      expect(report).to include("runs" => finished.size,
        "completion_rate" => completed.fdiv(finished.size).round(4),
        "blocks" => 1,
        "runs_needing_feedback" => 1)
      expect(completed).to be >= 1
      expect(finished.map { it["plan"] }).to include("001.00", "002.00")
      expect(report["time_to_answer"]).to include("count" => 1)
      expect(report["pr_outcomes"]).to include("merged" => 1)
      expect(report["usage_by_model"].map { it["adapter"] }.uniq).to eq(["claude"])
      expect(report["usage_by_model"].sum { it["input_tokens"] }).to eq(finished.size * 1_000)
    end
  end

  it "writes only allowlisted keys to the JSONL file" do
    answer_and_drain
    merge_a_pull_request
    lines = File.readlines(log_path).map { JSON.parse(it) }
    allowed = OpenLanes::Events::Event::PAYLOAD_KEYS.values.flatten.map(&:to_s)

    aggregate_failures do
      expect(lines).not_to be_empty
      expect(lines.flat_map { it["payload"].keys } - allowed).to be_empty
      expect(File.read(log_path)).not_to match(/Acme|Ada Example|total_cost_usd/)
    end
  end
end
