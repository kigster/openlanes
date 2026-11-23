# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Engine events", :tree do
  let(:log_dir) { Dir.mktmpdir("events") }
  let(:sink) { OpenLanes::Events::Sink.new(dir: log_dir, node: "n1", checkout: "c1", project: "demo") }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:events) { OpenLanes::Events::Log.new(dir: log_dir).events }
  let(:status) { "Completed" }
  let(:ok) { true }
  let(:offered) { [] }
  let(:cited) { [] }
  let(:executor) do
    lambda do |agent, subject, **|
      OpenLanes::Plans::PlanState.for(subject.feature.path).sign!(agent: agent.name, round: 1, status:)
      if status == "Blocked"
        File.write(File.join(subject.feature.path, "blocked.md"), "# Blocked\n\n## B1. Which?\n\n## B2. Where?\n")
      end
      OpenLanes::Execution::Executor::Result.new(ok:,
        note: "done",
        up: 1_000,
        down: 100,
        subagents: 0,
        delegated: 0,
        seconds: 1.0,
        offered:,
        cited:)
    end
  end

  def run(events_sink = sink)
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents: OpenLanes::Agents::Registry.new,
      sleeper: ->(_) {},
      events: events_sink).call
  end

  before { plans { |t| t.plan "000.00", :new, "needs-a-spec", files: { "spec.md" => spec_body } } }

  after { FileUtils.rm_rf(log_dir) }

  it "records the run and the agent from start to finish, under one run id" do
    run
    kinds = events.map(&:kind)

    expect(kinds.first).to eq("run_started")
    expect(kinds.last).to eq("run_finished")
    expect(kinds).to include("agent_started", "agent_finished")
    expect(events.map(&:run).uniq.size).to eq(1)
    finished = events.find { it.kind == "agent_finished" }
    expect(finished).to have_attributes(plan: "000.00", agent: "researcher", adapter: "claude")
    expect(finished.payload).to include("round" => 1,
      "input_tokens" => 1_000,
      "output_tokens" => 100,
      "estimated" => true,
      "status" => a_kind_of(String))
  end

  context "when the agent blocks" do
    let(:status) { "Blocked" }

    it "adds block_raised with the open question count" do
      run

      expect(events.find { it.kind == "block_raised" }&.payload).to include("blocks" => 2)
    end
  end

  context "when the attempt fails" do
    let(:ok) { false }
    let(:status) { "Started" }

    it "adds a failure carrying only the error class" do
      run

      failure = events.find { it.kind == "failure" }
      expect(failure.payload.keys).to contain_exactly("round", "invocation_start", "error_class")
    end
  end

  it "creates nothing when events are off" do
    run(OpenLanes::Events::NullSink.new)

    expect(Dir.children(log_dir)).to be_empty
  end

  context "when the prompt offered lessons" do
    let(:offered) { %w[L-0007 L-0012] }
    let(:cited) { %w[L-0012] }

    it "records each lesson offered and each one cited, keyed by plan, carrying only the id" do
      run

      offers = events.select { it.kind == "lesson_offered" }
      citations = events.select { it.kind == "lesson_cited" }
      by_invocation = ->(list) { list.group_by { [it.agent, it.payload["round"], it.payload["invocation_start"]] }.values }
      expect(by_invocation.call(offers)).to all(contain_exactly(have_attributes(payload: include("lesson" => "L-0007")),
        have_attributes(payload: include("lesson" => "L-0012"))))
      expect(citations.map { it.payload["lesson"] }.uniq).to eq(%w[L-0012])
      expect(by_invocation.call(citations).size).to eq(by_invocation.call(offers).size)
      expect(offers + citations).to all(have_attributes(plan: "000.00", agent: "researcher"))
      expect(citations.first.payload.keys).to contain_exactly("round", "invocation_start", "lesson")
    end
  end

  it "records no lesson event when nothing was offered" do
    run

    expect(events.map(&:kind)).not_to include("lesson_offered", "lesson_cited")
  end
end
